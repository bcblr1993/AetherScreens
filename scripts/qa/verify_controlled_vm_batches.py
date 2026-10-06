#!/usr/bin/env python3
"""Verify archived VM batches cover a complete selected iOS UI inventory.

This verifies only the selected iOS UI suite. Physical devices, other UI suites,
Screens parity and release readiness require separate acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile

from run_controlled_gesture_qa import CASES, SUITES


def verify_archive(path, inventory=CASES, suite="controlled"):
    with tarfile.open(path, "r:gz") as archive:
        files = {member.name: member for member in archive.getmembers() if member.isfile()}

        def read(name):
            with archive.extractfile(files[name]) as stream:
                return stream.read().decode("utf-8")

        roots = {name.split("/")[0] for name in files
                 if name.endswith("/gate.json") and name.count("/") == 1}
        workers = {name.split("/")[0] for name in files
                   if name.endswith("/request.json") and name.count("/") == 1
                   and name.startswith("aetherscreens-gui-command.")}
        if len(roots) != 1 or len(workers) != 1:
            raise ValueError(f"{path}: expected one result and one GUI worker")
        root, worker = roots.pop(), workers.pop()
        gate = json.loads(read(root + "/gate.json"))
        summary = json.loads(read(root + "/summary.json"))
        request = json.loads(read(worker + "/request.json"))
        receipt = json.loads(read(worker + "/result.json"))
        command = request["command"]
        if not request.get("exclusiveUI") or not any(
                PurePosixPath(argument).name == "run_controlled_gesture_qa.py"
                for argument in command):
            raise ValueError(f"{path}: not a guarded controlled-session command")
        declared_suite = command[command.index("--suite") + 1] if "--suite" in command else "controlled"
        if declared_suite != suite:
            raise ValueError(f"{path}: expected {suite} suite, command requests {declared_suite}")
        if suite == "url":
            delivery = json.loads(read(root + "/url-delivery.json"))
            if not (delivery.get("triggerObserved") and delivery.get("delivered")
                    and delivery.get("deliveryExitCode") == 0 and delivery.get("testProcessExit") == 0):
                raise ValueError(f"{path}: external system URL delivery failed or is absent")
        requested = [command[index + 1] for index, value in enumerate(command) if value == "--case"]
        if not requested:
            requested = list(inventory)
        if len(requested) != len(set(requested)) or not set(requested).issubset(inventory):
            raise ValueError(f"{path}: invalid requested inventory")
        expected = sorted("AetherScreensIOSUITests/" + case + "()" for case in requested)
        if gate["expectedCases"] != expected or gate["actualCases"] != expected:
            raise ValueError(f"{path}: recorded inventory differs from command")
        if (gate["processExit"] != 0 or gate["animationCompletionTimeouts"] != 0
                or summary["totalTestCount"] != len(requested)
                or summary["passedTests"] != len(requested)
                or summary["failedTests"] != 0 or summary["skippedTests"] != 0
                or summary["runtimeWarnings"] != []
                or receipt != {"exitCode": 0, "commandExitCode": 0}
                or worker + "/ui-collision.json" in files
                or "state = not running" not in read(worker + "/terminal-agent-state.txt")):
            raise ValueError(f"{path}: incomplete, failed or overlapping UI batch")
        actual = set()

        def visit(node):
            if node.get("nodeType") == "Test Case":
                if node["result"] != "Passed":
                    raise ValueError(f"{path}: case result is not Passed")
                actual.add(node["nodeIdentifier"])
            for child in node.get("children", []):
                visit(child)

        for node in json.loads(read(root + "/tests.json"))["testNodes"]:
            visit(node)
        if actual != set(expected):
            raise ValueError(f"{path}: authoritative test tree differs from inventory")
        manifest = json.loads(read(root + "/attachments/manifest.json"))
        if {test["testIdentifier"] for test in manifest} != set(expected):
            raise ValueError(f"{path}: attachment inventory differs from executed tests")
        for test in manifest:
            for attachment in test["attachments"]:
                if root + "/attachments/" + attachment["exportedFileName"] not in files:
                    raise ValueError(f"{path}: missing exported attachment")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        return {"archive": str(path), "archiveSHA256": digest,
                "cases": requested, "worker": worker}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=tuple(SUITES), default="controlled")
    parser.add_argument("--archive", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True, help="New verification file")
    args = parser.parse_args()
    inventory = SUITES[args.suite]
    batches = [verify_archive(path, inventory, args.suite) for path in args.archive]
    all_cases = [case for batch in batches for case in batch["cases"]]
    duplicates = sorted({case for case in all_cases if all_cases.count(case) > 1})
    missing = sorted(set(inventory) - set(all_cases))
    if duplicates or missing or len(all_cases) != len(inventory):
        raise ValueError(f"{args.suite} coverage incomplete: missing={missing}, duplicate={duplicates}")
    record = {"suite": args.suite, "suiteGatePassed": True,
              "controlledSessionGatePassed": args.suite == "controlled", "expectedCaseCount": len(inventory),
              "actualCaseCount": len(all_cases), "batches": batches,
              "physicalAcceptance": False, "fullProductAcceptance": False}
    with args.output.open("x") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")
    print(f"PASS: {len(inventory)} unique {args.suite} cases; other acceptance gates remain separate")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        raise SystemExit(str(error))
