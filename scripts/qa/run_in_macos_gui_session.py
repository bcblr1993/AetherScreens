#!/usr/bin/env python3
"""Run an owned QA command in the logged-in macOS launchd GUI session.

SSH's Security audit session can see a locked Keychain even when the console
Keychain is unlocked. A temporary LaunchAgent gives the command the actual GUI
session without changing Keychain policy or transmitting a password. Evidence
is retained; the agent is removed only after its worker has exited.
"""
import argparse
import json
import os
import pathlib
import plistlib
import signal
import subprocess
import sys
import tempfile
import time


def ui_processes():
    rows = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True).splitlines()
    return [line.strip().split(None, 2) for line in rows if len(line.strip().split(None, 2)) == 3]


def foreign_ui(processes):
    return [{"pid": int(pid), "path": path} for pid, _, path in processes
            if "UITests" in path and "Runner.app/" in path
            and not pathlib.Path(path).name.startswith("AetherScreens")]


def owned_xcodebuilds(processes, root_pid):
    descendants = {root_pid}
    while True:
        children = {int(pid) for pid, parent, _ in processes if int(parent) in descendants}
        expanded = descendants | children
        if expanded == descendants:
            break
        descendants = expanded
    return [int(pid) for pid, _, path in processes
            if int(pid) in descendants and pathlib.Path(path).name == "xcodebuild"]


def worker(workspace):
    request = json.loads((workspace / "request.json").read_text())
    collision = None
    with (workspace / "stdout.log").open("wb") as stdout, (workspace / "stderr.log").open("wb") as stderr:
        if not request.get("exclusiveUI", False):
            command_exit = subprocess.run(request["command"], cwd=request["cwd"], stdout=stdout, stderr=stderr).returncode
        else:
            foreign = [{"pid": int(pid), "path": path} for pid, _, path in ui_processes()
                       if "UITests" in path and "Runner.app/" in path]
            if foreign:
                collision = {"foreignRunners": foreign, "commandStarted": False, "interruptedOwnedXcodebuilds": []}
                command_exit = 2
            else:
                command = subprocess.Popen(request["command"], cwd=request["cwd"], stdout=stdout, stderr=stderr)
                interrupted = set()
                while command.poll() is None:
                    processes = ui_processes()
                    foreign = foreign_ui(processes)
                    if foreign and collision is None:
                        collision = {"foreignRunners": foreign, "commandStarted": True,
                                     "interruptedOwnedXcodebuilds": []}
                    if collision is not None:
                        # Stop only xcodebuild in this command's descendant tree.
                        # Leave the Python driver alive to export its xcresult.
                        for pid in owned_xcodebuilds(processes, command.pid):
                            if pid not in interrupted:
                                try:
                                    os.kill(pid, signal.SIGINT)
                                    interrupted.add(pid)
                                    collision["interruptedOwnedXcodebuilds"].append(pid)
                                except ProcessLookupError:
                                    pass
                        (workspace / "ui-collision.json").write_text(json.dumps(collision) + "\n")
                    time.sleep(0.5)
                command_exit = command.returncode
            if collision is not None:
                (workspace / "ui-collision.json").write_text(json.dumps(collision) + "\n")
                stderr.write(b"Shared VM UI collision; this command is not an accepted UI gate.\n")
    pending = workspace / "result.pending"
    pending.write_text(json.dumps({"exitCode": 2 if collision else command_exit,
                                  "commandExitCode": command_exit}) + "\n")
    pending.replace(workspace / "result.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", type=pathlib.Path, help=argparse.SUPPRESS)
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--evidence-parent", type=pathlib.Path, default=pathlib.Path(tempfile.gettempdir()))
    parser.add_argument("--exclusive-ui", action="store_true",
                        help="Reject competing UI runners and interrupt only this command's xcodebuild")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.worker:
        worker(args.worker)
        return
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("A command is required")
    domain = "gui/" + str(os.getuid())
    # Refuse headless sessions rather than silently falling back to SSH.
    subprocess.run(["launchctl", "print", domain], stdout=subprocess.DEVNULL, check=True)
    workspace = pathlib.Path(tempfile.mkdtemp(prefix="aetherscreens-gui-command.", dir=args.evidence_parent))
    label = "com.aethernative.aetherscreens.qa." + workspace.name.split(".")[-1]
    (workspace / "request.json").write_text(json.dumps({"command": command, "cwd": str(pathlib.Path(args.cwd).resolve()),
                                                       "exclusiveUI": args.exclusive_ui}) + "\n")
    agent = workspace / "agent.plist"
    agent.write_bytes(plistlib.dumps({
        "Label": label,
        "ProgramArguments": [sys.executable, str(pathlib.Path(__file__).resolve()), "--worker", str(workspace)],
        "RunAtLoad": True,
        "StandardOutPath": str(workspace / "worker-stdout.log"),
        "StandardErrorPath": str(workspace / "worker-stderr.log"),
    }))
    print("GUI command evidence: " + str(workspace), file=sys.stderr, flush=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(agent)], check=True)
    # On interruption leave a potentially live worker and its evidence intact.
    # Never bootout a running command, which would terminate its test process.
    while True:
        state = subprocess.run(["launchctl", "print", domain + "/" + label], capture_output=True, text=True, check=True).stdout
        if "state = not running" in state:
            if not (workspace / "result.json").exists():
                if "last exit code =" in state:
                    raise RuntimeError("GUI worker exited without a result; inspect " + str(workspace))
                time.sleep(0.5)
                continue
            break
        time.sleep(0.5)
    (workspace / "terminal-agent-state.txt").write_text(state)
    subprocess.run(["launchctl", "bootout", domain + "/" + label], check=True)
    result = json.loads((workspace / "result.json").read_text())
    for name, stream in [("stdout.log", sys.stdout.buffer), ("stderr.log", sys.stderr.buffer)]:
        with (workspace / name).open("rb") as log:
            while chunk := log.read(65536):
                stream.write(chunk)
        stream.flush()
    raise SystemExit(result["exitCode"])


if __name__ == "__main__":
    main()
