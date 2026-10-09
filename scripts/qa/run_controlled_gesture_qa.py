#!/usr/bin/env python3
"""Run the controlled iOS display/gesture/recovery scenarios and reject omissions.

Start gesture_rfb_fixture.py separately. This is a controlled
simulator/physical-input sub-gate, not actual Apple-server or complete-release
acceptance. Only generated QA credentials are used.
"""
import argparse
import base64
import atexit
import fcntl
from datetime import datetime, timezone
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import shutil
import tempfile
import time
import subprocess
import sys
import urllib.request
from uuid import uuid4

from usb_fixture_relay import USBFixtureRelay

REPO = Path(__file__).resolve().parents[2]

def export_performance_metrics(result, output, cases, physical_device=False):
    performance_cases = [case for case in cases if 'ScrollingPerformance' in case]
    if not performance_cases:
        return
    raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'metrics',
                                   '--path', str(result)], text=True)
    reports = json.loads(raw)
    summaries = []
    for case in performance_cases:
        identifier = 'AetherScreensIOSUITests/' + case + '()'
        matches = [report for report in reports if report.get('testIdentifier') == identifier]
        if len(matches) != 1:
            raise RuntimeError('Missing performance metric report for ' + identifier)
        for run in matches[0].get('testRuns', []):
            metrics = run.get('metrics', [])
            durations = [metric for metric in metrics if metric.get('identifier', '').endswith('Scroll_DraggingAndDeceleration.duration')]
            if len(durations) != 1 or len(durations[0].get('measurements', [])) != 3:
                raise RuntimeError('Expected three actual scroll measurements for ' + identifier)
            if durations[0].get('unitOfMeasurement') != 's' or not all(value > 0 for value in durations[0]['measurements']):
                raise RuntimeError('Invalid scroll duration measurements for ' + identifier)
            summaries.append({'testIdentifier': identifier, 'device': run.get('device'),
                              'environment': 'physical-device' if physical_device else 'simulator',
                              'hitchMeasurementsAvailable': any('hitch' in metric.get('identifier', '').lower() and metric.get('measurements') for metric in metrics),
                              'metrics': [{'name': metric.get('displayName'),
                                           'unit': metric.get('unitOfMeasurement'),
                                           'samples': metric.get('measurements', [])} for metric in metrics],
                              'scope': ('Fixed generated 64-computer dataset; six swipes per sample; no before/after comparison' if 'LargeLibrary' in case else 'Controlled small-list baseline; no before/after comparison or large-library gate')})
    if not summaries:
        raise RuntimeError('Performance report contains no measured test run')
    (output / 'metrics.json').write_text(raw)
    (output / 'metrics-summary.json').write_text(json.dumps(summaries, indent=2))

def acquire_clipboard_qa_lock(cases, device):
    if not any('Paste' in case or 'Clipboard' in case for case in cases):
        return None
    # Simulator host pasteboard synchronization can span devices/worktrees.
    directory = Path.home() / 'Library/Caches/AetherScreens-QA'
    directory.mkdir(parents=True, exist_ok=True)
    handle = (directory / 'clipboard.lock').open('a+')
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        raise RuntimeError('Another controlled clipboard QA run is active. Finish that run before starting this case.')
    handle.seek(0)
    handle.truncate()
    json.dump({'pid': os.getpid(), 'device': device}, handle)
    handle.flush()
    # Keep the lock through generated-data cleanup; the kernel releases it even
    # after an abrupt process exit. Never unlink a possibly held lock file.
    atexit.register(handle.close)
    return handle


CASES = (
    'testControlledStaticLockNotice',
    'testChineseControlledStaticLockNotice',
    'testControlledComputerPreview',
    'testChineseControlledComputerPreview',
    'testControlledDisplayQuality',
    'testChineseControlledDisplayQuality',
    'testControlledMobileSessionSelection',
    'testChineseControlledMobileSessionSelection',
    'testControlledFullscreenGestures',
    'testChineseControlledFullscreenGestures',
    'testControlledDisplaySelection',
    'testChineseControlledDisplaySelection',
    'testControlledRotationMapping',
    'testChineseControlledRotationMapping',
    'testControlledViewportNavigation',
    'testChineseControlledViewportNavigation',
    'testControlledZoomedTrackpadEdgeFollow',
    'testChineseControlledZoomedTrackpadEdgeFollow',
    'testControlledFloatingToolbar',
    'testChineseControlledFloatingToolbar',
    'testControlledCarouselToolbar',
    'testChineseControlledCarouselToolbar',
    'testControlledToolbarRepeat',
    'testChineseControlledToolbarRepeat',
    'testControlledToolbarRotation',
    'testControlledToolbarInteraction',
    'testChineseControlledToolbarInteraction',
    'testControlledFirstFrameTimeoutRecovery',
    'testChineseControlledFirstFrameTimeoutRecovery',
    'testControlledConnectionRecovery',
    'testChineseControlledConnectionRecovery',
    'testReceivedNativeGesturesOnControlledDesktop',
    'testReceivedChineseNativeGesturesOnControlledDesktop',
)


def run(command, log, check=True):
    with log.open('x') as output:
        return subprocess.run(command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT, check=check).returncode


def run_device_test(command, log, device_id):
    if not device_id:
        return run(command, log, check=False)
    with log.open('x') as output:
        process = subprocess.Popen(command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT)
        interference = None
        while process.poll() is None:
            if interference is None:
                try:
                    require_idle_device(device_id, ignore_pid=process.pid)
                except RuntimeError as error:
                    interference = {
                        'timeUTC': datetime.now(timezone.utc).isoformat(),
                        'ownTestPID': process.pid, 'reason': str(error),
                        'acceptanceValid': False,
                    }
                    (log.parent / 'device-interference.json').write_text(json.dumps(interference, indent=2) + '\n')
                    process.send_signal(signal.SIGINT)
            time.sleep(0.5)
        # Keep the result bundle, but never accept a contaminated run even if
        # xcodebuild finishes successfully after the interruption request.
        return 125 if interference else process.returncode


def tcp_port(value):
    port = int(value)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError('TCP port must be between 1 and 65535')
    return port


def require_idle_device(device_id, ignore_pid=None):
    """Reject observed competing tests without stopping another task's work."""
    processes = subprocess.run(['ps', '-axo', 'pid=,command='], check=True,
                               capture_output=True, text=True).stdout
    pattern = re.compile(r'\bid=' + re.escape(device_id) + r'(?:[,\s]|$)')
    conflicts = []
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if (len(fields) == 2 and fields[0] != str(ignore_pid)
                and Path(fields[1].split(None, 1)[0]).name == 'xcodebuild'
                and pattern.search(fields[1])):
            if re.search(r'\btest(?:-without-building)?\b', fields[1]):
                conflicts.append(fields[0])
    if conflicts:
        raise RuntimeError('Physical device is busy with xcodebuild test PID(s): ' + ', '.join(conflicts)
                           + '. Wait for those tests to finish before running this suite.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    destination_group = parser.add_mutually_exclusive_group(required=True)
    destination_group.add_argument('--simulator-id')
    destination_group.add_argument('--device-id', help='USB-connected physical device UDID')
    parser.add_argument('--development-team', help='Signing team required for a physical device')
    parser.add_argument('--simulator-keychain', action='store_true', help='Build the owned simulator test app with an isolated QA Keychain access group')
    parser.add_argument('--fixture-host', default='127.0.0.1', type=ipaddress.IPv4Address)
    parser.add_argument('--rfb-port', default=5999, type=tcp_port)
    parser.add_argument('--display-rfb-port', default=6000, type=tcp_port)
    parser.add_argument('--http-port', default=8768, type=tcp_port)
    parser.add_argument('--derived-data', type=Path, default=REPO / 'build/controlled-ui-derived')
    parser.add_argument('--output', type=Path, help='New artifact directory; must not exist')
    parser.add_argument('--case', action='append', choices=CASES + ('testControlledReducedMotionLockNotice', 'testControlledSystemSettingsInventory', 'testControlledReducedMotionKeyboardOverlays', 'testControlledSystemReducedMotionOff') + ('testControlledLargeLibraryScrollingPerformance', 'testControlledComputerPreviewScrollingPerformance', 'testControlledShortcutsCatalog', 'testControlledDisconnectAction', 'testChineseControlledDisconnectAction', 'testControlledSSHSettings', 'testChineseControlledSSHSettings', 'testControlledSSHKeyImportSelection', 'testChineseControlledSSHKeyImportSelection', 'testControlledSSHKeyReuse', 'testChineseControlledSSHKeyReuse', 'testControlledSSHKeyLibrary', 'testChineseControlledSSHKeyLibrary', 'testControlledSSHKeyReusePaste', 'testChineseControlledSSHKeyReusePaste', 'testControlledSSHKeyReuseInvalidPaste', 'testChineseControlledSSHKeyReuseInvalidPaste', 'testControlledSSHKeyLibraryPaste', 'testChineseControlledSSHKeyLibraryPaste', 'testControlledSSHKeyLibraryFile', 'testChineseControlledSSHKeyLibraryFile', 'testControlledSSHKeyLibraryExport', 'testChineseControlledSSHKeyLibraryExport', 'testControlledSSHKeyLibraryExportSave', 'testChineseControlledSSHKeyLibraryExportSave', 'testControlledSSHKeyLibraryFileDraft', 'testChineseControlledSSHKeyLibraryFileDraft', 'testControlledSSHKeyLibraryFileEncryptedDraft', 'testChineseControlledSSHKeyLibraryFileEncryptedDraft', 'testControlledSSHKeyLibraryFileEncrypted', 'testChineseControlledSSHKeyLibraryFileEncrypted'), help='Run explicit cases; omission defaults to the complete suite')
    args = parser.parse_args()
    if args.device_id and (not args.development_team or args.fixture_host.is_loopback):
        parser.error('Physical QA requires --development-team and the fixture LAN IPv4 address')
    if args.device_id:
        require_idle_device(args.device_id)
    fixture_host = str(args.fixture_host)
    try:
        with urllib.request.urlopen('http://' + fixture_host + ':' + str(args.http_port) + '/events', timeout=2) as response:
            if not isinstance(json.load(response), list):
                parser.error('Unexpected controlled fixture response')
    except (OSError, ValueError) as error:
        parser.error('Start scripts/qa/gesture_rfb_fixture.py first: ' + str(error))
    token = uuid4().hex
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = (args.output or REPO / f'build/controlled-gesture-{stamp}-{token[:8]}').resolve()
    output.mkdir(parents=True, exist_ok=False)
    derived = args.derived_data.resolve()
    is_simulator = args.simulator_id is not None
    cases = tuple(dict.fromkeys(args.case)) if args.case else (CASES if is_simulator else CASES + ('testPhysicalZoomedTrackpadEdgeFollow',))
    if args.device_id and any(case in cases for case in ('testControlledReducedMotionLockNotice', 'testControlledSystemSettingsInventory', 'testControlledReducedMotionKeyboardOverlays', 'testControlledSystemReducedMotionOff')):
        parser.error('Reduce Motion system-setting QA requires the disposable simulator')
    if args.device_id and any('LargeLibrary' in case for case in cases):
        parser.error('Large-library seeding requires the disposable simulator QA app')
    clipboard_lock_handle = acquire_clipboard_qa_lock(cases, args.simulator_id or args.device_id)
    relay = None if is_simulator else USBFixtureRelay(args.device_id, fixture_host, args.http_port, output)
    destination = ('platform=iOS Simulator,id=' + args.simulator_id) if is_simulator else ('platform=iOS,arch=arm64,id=' + args.device_id)
    print('Artifacts: ' + str(output), flush=True)
    if is_simulator:
        subprocess.run(['xcrun', 'simctl', 'bootstatus', args.simulator_id, '-b'], check=True)
    signing = ['CODE_SIGNING_ALLOWED=NO'] if is_simulator else ['DEVELOPMENT_TEAM=' + args.development_team]
    build_project = REPO / 'ios/AetherScreensIOS.xcodeproj'
    qa_keychain_group = None
    if is_simulator and (args.simulator_keychain or any('LargeLibrary' in case for case in cases) or any('SSHSettings' in case or 'SSHKeyImportSelection' in case or ('SSHKeyReuse' in case or 'SSHKeyLibrary' in case) for case in cases)):
        # Let Xcode package simulated entitlements into the simulator executable.
        # Adding iOS restricted entitlements to a host ad-hoc signature prevents
        # AMFI from launching it. This does not change production signing settings.
        entitlement_file = output / 'simulator-keychain.entitlements'
        qa_keychain_group = 'QAONLY0000.com.aethernative.aetherscreens.qa.simulator'
        with entitlement_file.open('xb') as entitlements:
            plistlib.dump({'application-identifier': 'QAONLY0000.$(PRODUCT_BUNDLE_IDENTIFIER)',
                          'keychain-access-groups': [qa_keychain_group]}, entitlements)
        # A command-line CODE_SIGN_ENTITLEMENTS applies to every Swift package
        # target and concatenates their entitlement sections into the app dylib.
        # Scope it only to the app in a disposable sibling project instead.
        original_project = build_project
        build_project = Path(tempfile.mkdtemp(prefix='.qa-keychain-', suffix='.xcodeproj', dir=REPO / 'ios'))
        atexit.register(shutil.rmtree, build_project, ignore_errors=True)
        shutil.copytree(original_project, build_project, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('xcuserdata'))
        project_data = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-',
                                                         str(build_project / 'project.pbxproj')]))
        objects = project_data['objects']
        if any(('SSHKeyReuse' in case or 'SSHKeyLibrary' in case or 'LargeLibrary' in case) for case in cases):
            # The fixture bootstrap exists only in this generated test app.
            # The production source/project are never edited for seeding.
            source = (REPO / 'ios/AetherScreensIOSApp.swift').read_text()
            anchor = 'struct AetherScreensIOSApp: App {\n'
            if source.count(anchor) != 1:
                raise RuntimeError('QA bootstrap app anchor is ambiguous')
            source = source.replace(anchor, anchor + '    init() {\n        do { try SSHKeyUIFixture.prepare(); try LargeLibraryUIFixture.prepare() }\n        catch { fatalError("Owned SSH key QA fixture failed") }\n    }\n')
            generated = output / 'AetherScreensIOSApp-QA.swift'
            vector_source = 'private enum SSHEncryptedQAData { static let key: Data? = nil; static let encrypted: Data? = nil }'
            if any('FileEncrypted' in case for case in cases):
                # Fresh, disposable QA material. No real user's private key or phrase.
                oracle = Path('/opt/homebrew/opt/openssl@3/bin/openssl')
                if not oracle.is_file():
                    raise RuntimeError('OpenSSL 3 is required for encrypted key UI QA')
                with tempfile.TemporaryDirectory(prefix='aetherscreens-encrypted-qa-') as scratch:
                    scratch = Path(scratch)
                    phrase = scratch / 'phrase'
                    phrase.write_text('QA-only encrypted import')
                    phrase.chmod(0o600)
                    key = scratch / 'key.pem'
                    encrypted = scratch / 'encrypted.pem'
                    subprocess.run([str(oracle), 'genpkey', '-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-256', '-out', str(key)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run([str(oracle), 'pkcs8', '-topk8', '-in', str(key), '-out', str(encrypted), '-v2', 'aes-256-cbc', '-v2prf', 'hmacWithSHA256', '-iter', '10000', '-passout', 'file:' + str(phrase)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    vector_source = 'private enum SSHEncryptedQAData { static let key: Data? = Data(base64Encoded: "' + base64.b64encode(key.read_bytes()).decode() + '"); static let encrypted: Data? = Data(base64Encoded: "' + base64.b64encode(encrypted.read_bytes()).decode() + '") }'
            generated.write_text(source + '\n' + vector_source + '\n' + (REPO / 'scripts/qa/ssh_key_ui_fixture.swift').read_text() + '\n' + (REPO / 'scripts/qa/large_library_ui_fixture.swift').read_text())
            references = [value for value in objects.values()
                          if value.get('isa') == 'PBXFileReference' and value.get('path') == 'AetherScreensIOSApp.swift']
            if len(references) != 1:
                raise RuntimeError('QA bootstrap source reference is ambiguous')
            references[0].update({'path': str(generated), 'sourceTree': '<absolute>'})
        if any('SSHKeyLibraryFile' in case or 'SSHKeyLibraryExportSave' in case for case in cases):
            # Expose only the disposable QA app's owned document to Files.
            qa_info = output / 'QA-Info.plist'
            with (REPO / 'ios/Info.plist').open('rb') as source_info:
                info = plistlib.load(source_info)
            info.update({'UIFileSharingEnabled': True, 'LSSupportsOpeningDocumentsInPlace': True})
            with qa_info.open('wb') as target_info:
                plistlib.dump(info, target_info)
        app_target = next(value for value in objects.values()
                          if value.get('isa') == 'PBXNativeTarget' and value.get('name') == 'AetherScreensIOS')
        for config in objects[app_target['buildConfigurationList']]['buildConfigurations']:
            objects[config]['buildSettings'].update({'CODE_SIGN_ENTITLEMENTS': str(entitlement_file),
                'CODE_SIGNING_ALLOWED': 'YES', 'CODE_SIGNING_REQUIRED': 'NO',
                'CODE_SIGN_IDENTITY': '-', 'DEVELOPMENT_TEAM': 'QAONLY0000'})
        if any('SSHKeyLibraryFile' in case or 'SSHKeyLibraryExportSave' in case for case in cases):
            for config in objects[app_target['buildConfigurationList']]['buildConfigurations']:
                objects[config]['buildSettings']['INFOPLIST_FILE'] = str(qa_info)
        with (build_project / 'project.pbxproj').open('wb') as project_file:
            plistlib.dump(project_data, project_file)
        for scheme in build_project.glob('xcshareddata/xcschemes/*.xcscheme'):
            scheme.write_text(scheme.read_text().replace(original_project.name, build_project.name))
        (output / 'simulator-project.json').write_text(json.dumps({'path': str(build_project),
            'keychainGroup': qa_keychain_group, 'scope': 'app target only; disposable QA project'}, indent=2) + '\n')
        signing = ['CODE_SIGNING_ALLOWED=YES']
    build_started = time.time()
    run(['xcodebuild', 'build-for-testing', '-project', str(build_project),
         '-scheme', 'AetherScreensIOS', '-destination', destination,
         '-derivedDataPath', str(derived), *signing], output / 'build.log')
    if args.device_id:
        require_idle_device(args.device_id)
    products = derived / 'Build/Products'
    if qa_keychain_group:
        simulated = derived / ('Build/Intermediates.noindex/' + build_project.stem + '.build/Debug-iphonesimulator/AetherScreensIOS.build/AetherScreensIOS.app-Simulated.xcent')
        if not simulated.exists() or plistlib.loads(simulated.read_bytes()).get('keychain-access-groups') != [qa_keychain_group]:
            raise RuntimeError('Xcode did not produce the isolated simulator Keychain entitlements')
    platform = 'iphonesimulator' if is_simulator else 'iphoneos'
    candidates = [path for path in products.glob('AetherScreensIOS_AetherScreensIOS_' + platform + '*.xctestrun')
                  if path.stat().st_mtime >= build_started - 1]
    if not candidates:
        raise RuntimeError('No freshly generated test configuration')
    current = max(candidates, key=lambda path: path.stat().st_mtime)
    configuration = plistlib.loads(current.read_bytes())
    for group in configuration['TestConfigurations']:
        for target in group['TestTargets']:
            target.setdefault('EnvironmentVariables', {})['AETHERSCREENS_GESTURE_QA'] = '1'
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_HOST'] = fixture_host
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_RFB_PORT'] = str(args.rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_DISPLAY_PORT'] = str(args.display_rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_HTTP_PORT'] = str(args.http_port)
            if relay:
                target['EnvironmentVariables']['AETHERSCREENS_QA_USB_RELAY'] = '1'
                target['EnvironmentVariables']['AETHERSCREENS_QA_USB_RELAY_DIR'] = relay.directory
    # Keep __TESTROOT__ valid, use a new path to avoid reusing discovery metadata,
    # and never replace the generated plan or any existing opt-in configuration.
    fresh = products / f'CONTROLLED_GESTURE_{token}.xctestrun'
    with fresh.open('xb') as plan:
        plistlib.dump(configuration, plan)
    result = output / 'result.xcresult'
    command = ['xcodebuild', 'test-without-building', '-xctestrun', str(fresh),
               '-destination', destination, '-parallel-testing-enabled', 'NO',
               *['-only-testing:AetherScreensIOSUITests/AetherScreensIOSUITests/' + case for case in cases]]
    if is_simulator:
        # Preserve XCTest failures/attachments without ten-minute simulator sysdiagnose waits.
        # Physical acceptance retains Xcode's default verbose failure diagnostics.
        command += ['-collect-test-diagnostics', 'never']
    try:
        if relay:
            relay.start()
        enumeration = output / 'enumeration.json'
        run([*command, '-enumerate-tests', '-test-enumeration-style', 'flat',
             '-test-enumeration-format', 'json', '-test-enumeration-output-path', str(enumeration)], output / 'enumeration.log')
        discovered = json.loads(enumeration.read_text())
        enabled = {test['identifier'] for group in discovered.get('values', [])
                   for test in group.get('enabledTests', [])}
        expected_discovery = {'AetherScreensIOSUITests/AetherScreensIOSUITests/' + case + '()' for case in cases}
        if discovered.get('errors') or enabled != expected_discovery:
            raise RuntimeError(f'Controlled test discovery incomplete: missing={sorted(expected_discovery - enabled)}, unexpected={sorted(enabled - expected_discovery)}; inspect {output}')
        test_exit = run_device_test([*command, '-resultBundlePath', str(result)], output / 'tests.log', args.device_id)
    finally:
        if relay:
            relay.stop()
        fresh.unlink()
    if is_simulator and any(('SSHKeyReuse' in case or 'SSHKeyLibrary' in case) for case in cases):
        # XCTest aborts can bypass Swift defer. Clean generated identities only
        # after xcodebuild is terminal, using the installed disposable QA app.
        require_idle_device(args.simulator_id)
        container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container',
            args.simulator_id, 'com.aethernative.aetherscreens.ios', 'data'], text=True).strip())
        journal = container / 'Library/Caches/ssh-key-qa-owned.json'
        tokens = json.loads(journal.read_text()) if journal.exists() else []
        for token in tokens:
            from uuid import UUID
            assert str(UUID(token)).upper() == token
            environment = os.environ.copy()
            environment.update({'SIMCTL_CHILD_AETHERSCREENS_SSH_KEY_QA_TOKEN': token,
                                'SIMCTL_CHILD_AETHERSCREENS_SSH_KEY_QA_ACTION': 'cleanup'})
            subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process',
                args.simulator_id, 'com.aethernative.aetherscreens.ios'], env=environment,
                check=True, stdout=subprocess.DEVNULL)
            deadline = time.monotonic() + 10
            while token in json.loads(journal.read_text()) and time.monotonic() < deadline:
                time.sleep(0.2)
            if token in json.loads(journal.read_text()):
                raise RuntimeError('Owned SSH key cleanup did not complete')
        (output / 'ssh-key-cleanup.json').write_text(json.dumps({'generatedIdentityCount': len(tokens),
            'remaining': json.loads(journal.read_text()) if journal.exists() else []}, indent=2))
        if any('SSHKeyLibraryExportSave' in case for case in cases):
            import re
            # Defers may have emptied the journal already; recover only QA seed IDs
            # from their explicit export-button interactions, never key contents.
            export_tokens = set(tokens) | set(re.findall(r'ssh-library-export-([A-F0-9-]{36})',
                                                        (output / 'tests.log').read_text()))
            remaining_files = sum((container / 'Documents' / name).exists()
                                  for token in export_tokens
                                  for name in ('QA-Key-' + token + '.pem',
                                               'QA-Export-' + token, 'QA-Export-' + token + '.txt'))
            (output / 'ssh-export-file-cleanup.json').write_text(json.dumps({
                'generatedSeedCount': len(export_tokens), 'remainingOwnedFiles': remaining_files}, indent=2) + '\n')
            if remaining_files:
                raise RuntimeError('Owned SSH export files remain after cleanup')
    if is_simulator and any('LargeLibrary' in case for case in cases):
        require_idle_device(args.simulator_id)
        container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container',
            args.simulator_id, 'com.aethernative.aetherscreens.ios', 'data'], text=True).strip())
        journal = container / 'Library/Caches/large-library-qa-owned.json'
        owned = json.loads(journal.read_text()) if journal.exists() else {}
        for token in owned:
            from uuid import UUID
            assert str(UUID(token)).upper() == token
            environment = os.environ.copy()
            environment.update({'SIMCTL_CHILD_AETHERSCREENS_LIBRARY_QA_TOKEN': token,
                                'SIMCTL_CHILD_AETHERSCREENS_LIBRARY_QA_ACTION': 'cleanup'})
            subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process',
                args.simulator_id, 'com.aethernative.aetherscreens.ios'], env=environment,
                check=True, stdout=subprocess.DEVNULL)
            deadline = time.monotonic() + 10
            while token in json.loads(journal.read_text()) and time.monotonic() < deadline:
                time.sleep(0.2)
            if token in json.loads(journal.read_text()):
                raise RuntimeError('Owned large-library cleanup did not complete')
        remaining = json.loads(journal.read_text()) if journal.exists() else {}
        (output / 'large-library-cleanup.json').write_text(json.dumps({'remaining': remaining}, indent=2))
    reports = {}
    export_performance_metrics(result, output, cases, physical_device=bool(args.device_id))
    for name in ('summary', 'tests'):
        raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', name, '--path', str(result)], text=True)
        (output / (name + '.json')).write_text(raw)
        reports[name] = json.loads(raw)
    actual = set()
    def visit(node):
        if node.get('nodeType') == 'Test Case':
            actual.add(node['nodeIdentifier'])
        for child in node.get('children', []):
            visit(child)
    for node in reports['tests']['testNodes']:
        visit(node)
    expected = {'AetherScreensIOSUITests/' + case + '()' for case in cases}
    summary = reports['summary']
    if (test_exit != 0 or actual != expected or summary.get('totalTestCount') != len(cases)
            or summary.get('passedTests') != len(cases)
            or summary.get('failedTests') != 0 or summary.get('skippedTests') != 0
            or summary.get('runtimeWarnings') != []):
        raise RuntimeError(f'Controlled QA incomplete: missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}; inspect {output}')
    print(f'PASS: all {len(cases)} requested cases executed, no skips/failures/runtime warnings', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('Controlled QA failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
