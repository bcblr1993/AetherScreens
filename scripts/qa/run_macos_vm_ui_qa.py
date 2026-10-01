#!/usr/bin/env python3
"""Run the Mac UI suite in an existing Tart macOS 27 VM using SSH key access."""
import argparse
import json
import pathlib
import plistlib
import shlex
import subprocess


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vm", default="macos27")
    parser.add_argument("--user", default="chenxu")
    parser.add_argument("--developer-dir", required=True, help="Xcode Contents/Developer path inside the VM")
    parser.add_argument("--app", required=True, type=pathlib.Path, help="Separately identified .vmqa app bundle")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if not info.get("CFBundleIdentifier", "").endswith(".vmqa"):
        parser.error("Use an isolated QA app with a bundle identifier ending in .vmqa")
    # Tart supplies the destination. Never start, stop, or reset an existing VM.
    ip = run(["tart", "ip", args.vm], capture_output=True).stdout.strip()
    target = f"{args.user}@{ip}"
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", target]

    def remote(command, **kwargs):
        return run(ssh + [command], **kwargs)

    version = remote("sw_vers -productVersion", capture_output=True).stdout.strip()
    virtual = remote("sysctl -n kern.hv_vmm_present", capture_output=True).stdout.strip()
    if not version.startswith("27.") or virtual != "1":
        parser.error("The destination must be a macOS 27 virtual machine")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    workspace = remote("mktemp -d /Users/" + shlex.quote(args.user) + "/aetherscreens-ui-qa.XXXXXX", capture_output=True).stdout.strip()
    (output / "environment.json").write_text(json.dumps({"vm": args.vm, "macOS": version, "workspace": workspace}, indent=2))
    root = pathlib.Path(__file__).resolve().parents[2]
    run(["scp", "-q", "-r", str(root / "macos/UITests"), str(app), f"{target}:{workspace}/"])
    developer = shlex.quote(args.developer_dir)
    xcode = shlex.quote(args.developer_dir + "/usr/bin/xcodebuild")
    prefix = f"env DEVELOPER_DIR={developer} {xcode}"
    derived = workspace + "/DerivedData"
    project = workspace + "/UITests/AetherScreensMacUITests.xcodeproj"
    with (output / "build.log").open("w") as log:
        remote(f"{prefix} build-for-testing -project {shlex.quote(project)} -scheme AetherScreensMacUITests -destination 'platform=macOS,arch=arm64' -derivedDataPath {shlex.quote(derived)}", stdout=log, stderr=subprocess.STDOUT)
    products = derived + "/Build/Products"
    original = remote(f"find {shlex.quote(products)} -maxdepth 1 -name '*.xctestrun'", capture_output=True).stdout.splitlines()
    if len(original) != 1:
        raise RuntimeError("Expected exactly one generated XCTest run configuration")
    config = output / "VM.xctestrun"
    run(["scp", "-q", f"{target}:{original[0]}", str(config)])
    data = plistlib.loads(config.read_bytes())

    def configure(value):
        if isinstance(value, dict):
            if "TestBundlePath" in value:
                value.setdefault("EnvironmentVariables", {})["AETHERSCREENS_MAC_QA_APP_PATH"] = workspace + "/" + app.name
            for child in list(value.values()):
                configure(child)
        elif isinstance(value, list):
            for child in value:
                configure(child)

    configure(data)
    config.write_bytes(plistlib.dumps(data))
    remote_config = products + "/VM.xctestrun"
    run(["scp", "-q", str(config), f"{target}:{remote_config}"])
    result = workspace + "/result.xcresult"
    print("Executing in VM. Complete any Enable UI Automation password prompt inside the VM.", flush=True)
    with (output / "tests.log").open("w") as log:
        completed = subprocess.run(ssh + [f"{prefix} test-without-building -xctestrun {shlex.quote(remote_config)} -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -resultBundlePath {shlex.quote(result)}"], stdout=log, stderr=subprocess.STDOUT)
    run(["scp", "-q", "-r", f"{target}:{result}", str(output / "result.xcresult")])
    summary = run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(output / "result.xcresult")], capture_output=True).stdout
    (output / "summary.json").write_text(summary)
    report = json.loads(summary)
    if completed.returncode or report.get("passedTests") != 2 or report.get("totalTestCount") != 2 or report.get("failedTests") or report.get("skippedTests") or report.get("runtimeWarnings"):
        raise SystemExit("VM UI acceptance failed; inspect tests.log and summary.json. No automatic retry.")
    print("VM Mac UI: 2 passed, no failures, skips or runtime warnings.")


if __name__ == "__main__":
    main()
