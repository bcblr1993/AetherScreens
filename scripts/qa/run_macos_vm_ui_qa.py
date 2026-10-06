#!/usr/bin/env python3
"""Run the Mac UI suite in an existing Tart macOS 27 VM using SSH key access."""
import argparse
from contextlib import contextmanager
import json
import hashlib
import pathlib
import plistlib
import shlex
import subprocess
import tarfile

INITIAL_CASES = ("testEnglishQuickConnectValidation", "testChineseQuickConnectValidation")
CONTROLLED_CASES = ("testEnglishControlledSession", "testChineseControlledSession")
SSH_EDITOR_CASES = ("testEnglishSSHTrustEditor", "testChineseSSHTrustEditor")


def run(args, **kwargs):
    return subprocess.run(args, check=kwargs.pop("check", True), text=True, **kwargs)



@contextmanager
def closed_workspace_evidence(remote, target, workspace, output, app_name):
    """Retain independently verified evidence before removing owned build copies."""
    try:
        yield
    finally:
        # A terminal command alone does not prove its application exited. Leave
        # every file intact if any process still executes from this workspace.
        archive_script = """import pathlib,subprocess,tarfile,json,hashlib
w=pathlib.Path(WORKSPACE)
assert w.parent == pathlib.Path('/Users/USER') and w.name.startswith('aetherscreens-ui-qa.')
assert not w.is_symlink()
assert str(w) not in subprocess.check_output(['ps','-axo','comm='],text=True), 'Workspace still active; retain artifacts'
a=w/'closed-evidence.tgz'
with tarfile.open(a,'w:gz') as archive:
 for relative in ['result.xcresult','DerivedData/Logs/Test','enumeration.json']:
  p=w/relative
  if p.exists(): archive.add(p,arcname=relative)
with a.open('rb') as f:
 digest=hashlib.sha256()
 for block in iter(lambda:f.read(1048576),b''):digest.update(block)
print(digest.hexdigest())
""".replace('WORKSPACE', repr(workspace)).replace('/Users/USER', str(pathlib.PurePosixPath(workspace).parent))
        try:
            digest = remote('/usr/bin/python3 -c ' + shlex.quote(archive_script), capture_output=True).stdout.strip()
            archive = output / 'closed-evidence.tgz'
            run(['scp', '-q', f'{target}:{workspace}/closed-evidence.tgz', str(archive)])
            with archive.open('rb') as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest()
            if actual != digest:
                raise RuntimeError('Closed evidence hash mismatch; guest artifacts retained')
            (output / 'closed-evidence.sha256').write_text(digest + '\n')
            cleanup_script = """import pathlib,subprocess,shutil,json
w=pathlib.Path(WORKSPACE)
assert not w.is_symlink()
assert str(w) not in subprocess.check_output(['ps','-axo','comm='],text=True), 'Workspace became active; retain artifacts'
before=shutil.disk_usage(w).free;removed=[]
for name in ['DerivedData','result.xcresult','result.tgz','closed-evidence.tgz',APP_NAME]:
 p=w/name
 assert p.parent == w and not p.is_symlink()
 if not p.exists():continue
 n=int(subprocess.check_output(['du','-sk',str(p)],text=True).split()[0])*1024
 if p.is_dir():shutil.rmtree(p)
 else:p.unlink()
 removed.append({'path':str(p),'allocatedBytes':n,'verifiedAbsent':not p.exists()})
print(json.dumps({'removed':removed,'freeBytesBefore':before,'freeBytesAfter':shutil.disk_usage(w).free,'sourceRetained':(w/'UITests').exists()}))
""".replace('WORKSPACE', repr(workspace)).replace('APP_NAME', repr(app_name))
            record = json.loads(remote('/usr/bin/python3 -c ' + shlex.quote(cleanup_script), capture_output=True).stdout)
            record['preservedArchiveSHA256'] = digest
            (output / 'verified-closed-cleanup.json').write_text(json.dumps(record, indent=2) + '\n')
        except Exception as error:
            (output / 'cleanup-error.txt').write_text(str(error) + '\nGuest artifacts retained wherever cleanup was not verified.\n')
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vm", default="macos27")
    parser.add_argument("--user", default="chenxu")
    parser.add_argument("--developer-dir", required=True, help="Xcode Contents/Developer path inside the VM")
    parser.add_argument("--app", required=True, type=pathlib.Path, help="Separately identified .vmqa app bundle")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--suite", choices=("initial", "controlled", "ssh-editor", "all"), default="initial")
    parser.add_argument("--ssh-fixture-metadata", type=pathlib.Path, help="Public port/fingerprint of the owned VM SSH fixture")
    parser.add_argument("--request-automation-authorization", action="store_true",
                        help="Allow XCTest to request authenticated UI Automation inside the VM; does not change authentication policy")
    args = parser.parse_args()
    cases = {"initial": INITIAL_CASES, "controlled": CONTROLLED_CASES,
             "ssh-editor": SSH_EDITOR_CASES,
             "all": INITIAL_CASES + CONTROLLED_CASES + SSH_EDITOR_CASES}[args.suite]
    metadata = json.loads(args.ssh_fixture_metadata.read_text()) if args.ssh_fixture_metadata else None
    if any(case in SSH_EDITOR_CASES for case in cases) and metadata is None:
        parser.error("SSH editor cases require the owned SSH fixture metadata")
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
    # Simulator UI can pass while the Mac console is locked. Native XCTest
    # then waits for automation mode rather than executing any application case.
    session_probe = """import CoreGraphics
if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
    if session["CGSSessionScreenIsLocked"] as? Bool == true { print("LOCKED") }
    else if session["kCGSessionLoginDoneKey"] as? Bool == true { print("READY") }
    else { print("UNAVAILABLE") }
} else { print("UNAVAILABLE") }
"""
    session = remote("env DEVELOPER_DIR=" + shlex.quote(args.developer_dir)
                     + " /usr/bin/swift -e " + shlex.quote(session_probe),
                     capture_output=True).stdout.strip()
    if session != "READY":
        parser.error("The VM console must be unlocked before native Mac UI testing; current state: " + session)

    def require_idle_ui():
        processes = remote("ps -axo pid=,comm=", capture_output=True).stdout.splitlines()
        active = [line.strip() for line in processes if "UITests" in line and "Runner.app/" in line]
        if active:
            parser.error("The shared VM has live UI test runners; wait for them to exit: " + "; ".join(active))

    require_idle_ui()
    # Keychain and XCTest must share the console's Security audit session.
    # launchctl asuser alone does not move an SSH process into that session.
    helper_root = remote("mktemp -d /Users/" + shlex.quote(args.user) + "/aetherscreens-gui-qa.XXXXXX", capture_output=True).stdout.strip()
    helper = pathlib.Path(__file__).with_name("run_in_macos_gui_session.py")
    run(["scp", "-q", str(helper), f"{target}:{helper_root}/"])

    def gui_remote(command, **kwargs):
        return remote("/usr/bin/python3 " + shlex.quote(helper_root + "/" + helper.name)
                      + " --evidence-parent " + shlex.quote(helper_root)
                      + " --exclusive-ui"
                      + " -- /bin/zsh -c " + shlex.quote(command), **kwargs)

    if any(case in SSH_EDITOR_CASES for case in cases):
        # A logged-in console does not prove its file-based login Keychain is
        # unlocked. This suite must actually save credentials and remembered
        # trust, so fail before transferring/building when that cannot succeed.
        keychain_probe = """import Foundation
import Security
var keychain: SecKeychain?
let defaultStatus = SecKeychainCopyDefault(&keychain)
var flags: SecKeychainStatus = 0
let status = SecKeychainGetStatus(keychain, &flags)
let ready = defaultStatus == errSecSuccess && status == errSecSuccess &&
    flags & SecKeychainStatus(kSecUnlockStateStatus) != 0 &&
    flags & SecKeychainStatus(kSecWritePermStatus) != 0
let result: [String: Any] = ["ready": ready, "defaultStatus": defaultStatus, "status": status, "flags": flags]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
"""
        readiness = json.loads(gui_remote("env DEVELOPER_DIR=" + shlex.quote(args.developer_dir)
            + " /usr/bin/swift -e " + shlex.quote(keychain_probe), capture_output=True).stdout)
        if not readiness["ready"]:
            parser.error("SSH trust acceptance requires the VM login Keychain to be unlocked and writable; "
                         + json.dumps(readiness, sort_keys=True)
                         + ". Unlock it inside macos27 before rerunning; no test workspace was created.")
    automation = gui_remote("/usr/bin/automationmodetool", capture_output=True).stdout.strip()
    if "automation mode is enabled." not in automation.lower() and not args.request_automation_authorization:
        parser.error("The VM requires UI Automation authorization before native testing: "
                     + automation + ". No test workspace was created.")
    if "automation mode is enabled." not in automation.lower():
        print("XCTest will request authenticated UI Automation inside the VM. Existing authentication policy is retained.", flush=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    workspace = remote("mktemp -d /Users/" + shlex.quote(args.user) + "/aetherscreens-ui-qa.XXXXXX", capture_output=True).stdout.strip()
    (output / "environment.json").write_text(json.dumps({"vm": args.vm, "macOS": version, "workspace": workspace}, indent=2))
    (output / "gui-session.json").write_text(json.dumps({"helperWorkspace": helper_root,
        "executionSession": "launchd GUI", "helperSHA256": hashlib.sha256(helper.read_bytes()).hexdigest()}, indent=2))
    with closed_workspace_evidence(remote, target, workspace, output, app.name):
        root = pathlib.Path(__file__).resolve().parents[2]
        run(["scp", "-q", "-r", str(root / "macos/UITests"), str(app), f"{target}:{workspace}/"])
        developer = shlex.quote(args.developer_dir)
        xcode = shlex.quote(args.developer_dir + "/usr/bin/xcodebuild")
        prefix = f"env DEVELOPER_DIR={developer} {xcode}"
        derived = workspace + "/DerivedData"
        project = workspace + "/UITests/AetherScreensMacUITests.xcodeproj"
        with (output / "build.log").open("w") as log:
            gui_remote(f"{prefix} build-for-testing -project {shlex.quote(project)} -scheme AetherScreensMacUITests -destination 'platform=macOS,arch=arm64' -derivedDataPath {shlex.quote(derived)}", stdout=log, stderr=subprocess.STDOUT)
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
                    if metadata is not None:
                        value["EnvironmentVariables"]["AETHERSCREENS_SSH_QA_PORT"] = str(metadata["port"])
                        value["EnvironmentVariables"]["AETHERSCREENS_SSH_QA_FINGERPRINT"] = metadata["fingerprint"]
                    if args.suite != "initial":
                        value["EnvironmentVariables"]["AETHERSCREENS_MAC_CONTROLLED_QA"] = "1"
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
        selected = " ".join(shlex.quote("-only-testing:AetherScreensMacUITests/AetherScreensMacUITests/" + case) for case in cases)
        # Keep only this VM awake while the owned XCTest process runs. The utility
        # releases its assertions automatically when xcodebuild exits.
        test_command = f"/usr/bin/caffeinate -dims {prefix} test-without-building -xctestrun {shlex.quote(remote_config)} -destination 'platform=macOS,arch=arm64' -derivedDataPath {shlex.quote(derived)} -parallel-testing-enabled NO -collect-test-diagnostics never {selected}"
        enumeration_path = workspace + "/enumeration.json"
        require_idle_ui()
        with (output / "enumeration.log").open("x") as log:
            gui_remote(test_command + " -enumerate-tests -test-enumeration-style flat -test-enumeration-format json -test-enumeration-output-path " + shlex.quote(enumeration_path), stdout=log, stderr=subprocess.STDOUT)
        run(["scp", "-q", f"{target}:{enumeration_path}", str(output / "enumeration.json")])
        discovered = json.loads((output / "enumeration.json").read_text())
        enabled = {test["identifier"] for group in discovered.get("values", []) for test in group.get("enabledTests", [])}
        expected_discovery = {"AetherScreensMacUITests/AetherScreensMacUITests/" + case + "()" for case in cases}
        if discovered.get("errors") or enabled != expected_discovery:
            raise RuntimeError("Mac test discovery differs from the requested suite; inspect enumeration.json")
        print("Executing in VM. Complete any Enable UI Automation password prompt inside the VM.", flush=True)
        require_idle_ui()
        with (output / "tests.log").open("w") as log:
            completed = gui_remote(test_command + " -resultBundlePath " + shlex.quote(result), stdout=log, stderr=subprocess.STDOUT, check=False)
        remote_archive = workspace + "/result.tgz"
        remote("tar -czf " + shlex.quote(remote_archive) + " -C " + shlex.quote(workspace) + " result.xcresult")
        archive_sha = remote("shasum -a 256 " + shlex.quote(remote_archive), capture_output=True).stdout.split()[0]
        archive = output / "result.tgz"
        run(["scp", "-q", f"{target}:{remote_archive}", str(archive)])
        if hashlib.sha256(archive.read_bytes()).hexdigest() != archive_sha:
            raise RuntimeError("Mac result archive hash mismatch; guest evidence preserved")
        with tarfile.open(archive) as bundle:
            bundle.extractall(output, filter="data")
        (output / "result.sha256").write_text(archive_sha + "\n")
        remote("rm " + shlex.quote(remote_archive))
        summary = run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(output / "result.xcresult")], capture_output=True).stdout
        (output / "summary.json").write_text(summary)
        report = json.loads(summary)
        inventory = run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(output / "result.xcresult")], capture_output=True).stdout
        (output / "tests.json").write_text(inventory)
        with (output / "attachments-export.log").open("x") as log:
            run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(output / "result.xcresult"),
                 "--output-path", str(output / "attachments")], stdout=log, stderr=subprocess.STDOUT)
        if not (output / "attachments/manifest.json").is_file():
            raise RuntimeError("Mac UI attachment export did not produce a manifest")
        actual = set()
        def visit(node):
            if node.get("nodeType") == "Test Case":
                actual.add(node["nodeIdentifier"])
            for child in node.get("children", []):
                visit(child)
        for node in json.loads(inventory).get("testNodes", []):
            visit(node)
        expected = {"AetherScreensMacUITests/" + case + "()" for case in cases}
        timeouts = (output / "tests.log").read_text().count("App animations complete notification not received")
        (output / "gate.json").write_text(json.dumps({"processExit": completed.returncode,
            "expectedCases": sorted(expected), "actualCases": sorted(actual),
            "animationCompletionTimeouts": timeouts}, indent=2))
        if completed.returncode or actual != expected or timeouts or report.get("passedTests") != len(cases) or report.get("totalTestCount") != len(cases) or report.get("failedTests") or report.get("skippedTests") or report.get("runtimeWarnings"):
            raise SystemExit("VM UI acceptance failed; inspect tests.log and summary.json. No automatic retry.")
        print(f"VM Mac UI: all {len(cases)} requested cases passed, no failures, skips or runtime warnings.")



if __name__ == "__main__":
    main()
