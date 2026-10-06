#!/usr/bin/env python3
"""Run the Mac UI suite on a Tart VM or explicitly selected macOS 27 host using SSH key access."""
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
    parser.add_argument("--host", help="Explicitly authorized physical macOS 27 test host; bypasses Tart discovery")
    parser.add_argument("--user", default="chenxu")
    parser.add_argument("--developer-dir", required=True, help="Xcode Contents/Developer path inside the VM")
    parser.add_argument("--app", required=True, type=pathlib.Path, help="Separately identified .vmqa app bundle")
    parser.add_argument("--release-candidate", action="store_true", help="Test the unmodified, signed production candidate explicitly")
    parser.add_argument("--native-input", action="store_true", help="Also verify received native input against a separately running loopback fixture")
    parser.add_argument("--rfb-port", type=int, default=6399)
    parser.add_argument("--http-port", type=int, default=8868)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identifier = info.get("CFBundleIdentifier", "")
    if args.release_candidate:
        if identifier != "com.aethernative.aetherscreens":
            parser.error("The production candidate must have the AetherScreens bundle identifier")
        run(["codesign", "--verify", "--deep", "--strict", str(app)])
        run(["spctl", "--assess", "--type", "execute", str(app)])
    elif not identifier.endswith(".vmqa"):
        parser.error("Use an isolated QA app with a bundle identifier ending in .vmqa")
    # Tart supplies the destination. Never start, stop, or reset an existing VM.
    ip = args.host or run(["tart", "ip", args.vm], capture_output=True).stdout.strip()
    target = f"{args.user}@{ip}"
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", target]

    def remote(command, **kwargs):
        return run(ssh + [command], **kwargs)

    version = remote("sw_vers -productVersion", capture_output=True).stdout.strip()
    virtual = remote("sysctl -n kern.hv_vmm_present", capture_output=True).stdout.strip()
    if not version.startswith("27.") or (not args.host and virtual != "1"):
        parser.error("The destination must be macOS 27; VM discovery also requires virtualization")
    if not all(1 <= port <= 65535 for port in (args.rfb_port, args.http_port)):
        parser.error("Fixture ports must be between 1 and 65535")
    if args.native_input:
        events = remote("curl -fsS --max-time 3 http://127.0.0.1:" + str(args.http_port) + "/events", capture_output=True).stdout
        if not isinstance(json.loads(events), list):
            parser.error("Start the controlled gesture fixture on the test Mac first")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    workspace = remote("mktemp -d /Users/" + shlex.quote(args.user) + "/aetherscreens-ui-qa.XXXXXX", capture_output=True).stdout.strip()
    (output / "environment.json").write_text(json.dumps({"host": ip, "environment": "physical" if args.host else "vm", "vm": None if args.host else args.vm, "macOS": version, "workspace": workspace}, indent=2))
    root = pathlib.Path(__file__).resolve().parents[2]
    run(["scp", "-q", "-r", str(root / "macos/UITests"), str(app), f"{target}:{workspace}/"])
    if args.release_candidate:
        candidate = shlex.quote(workspace + "/" + app.name)
        remote("codesign --verify --deep --strict " + candidate)
        remote("spctl --assess --type execute " + candidate)
    # XCTest launches by bundle identifier. Replace Launch Services' stale
    # registration when an earlier isolated QA copy has the same identifier.
    remote("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "
           + shlex.quote(workspace + "/" + app.name))
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
                environment = value.setdefault("EnvironmentVariables", {})
                environment["AETHERSCREENS_MAC_QA_APP_PATH"] = workspace + "/" + app.name
                if args.native_input:
                    environment["AETHERSCREENS_MAC_QA_RFB_PORT"] = str(args.rfb_port)
                    environment["AETHERSCREENS_MAC_QA_HTTP_PORT"] = str(args.http_port)
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
    print("Executing on selected Mac. Complete any Enable UI Automation prompt on that Mac.", flush=True)
    with (output / "tests.log").open("w") as log:
        selection = "" if args.native_input else " -only-testing:AetherScreensMacUITests/AetherScreensMacUITests/testEnglishQuickConnectValidation -only-testing:AetherScreensMacUITests/AetherScreensMacUITests/testChineseQuickConnectValidation"
        completed = subprocess.run(ssh + [f"{prefix} test-without-building -xctestrun {shlex.quote(remote_config)} -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -resultBundlePath {shlex.quote(result)}{selection}"], stdout=log, stderr=subprocess.STDOUT)
    run(["scp", "-q", "-r", f"{target}:{result}", str(output / "result.xcresult")])
    summary = run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(output / "result.xcresult")], capture_output=True).stdout
    (output / "summary.json").write_text(summary)
    report = json.loads(summary)
    expected = 3 if args.native_input else 2
    if completed.returncode or report.get("passedTests") != expected or report.get("totalTestCount") != expected or report.get("failedTests") or report.get("skippedTests") or report.get("runtimeWarnings"):
        raise SystemExit("Mac UI acceptance failed; inspect tests.log and summary.json. No automatic retry.")
    print(f"Mac UI: {expected} passed, no failures, skips or runtime warnings.")


if __name__ == "__main__":
    main()
