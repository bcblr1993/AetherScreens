#!/usr/bin/env python3
"""Run the controlled iOS remote-session or library UI gate and reject omissions.

Start gesture_rfb_fixture.py separately. This is a controlled
simulator/physical-input sub-gate, not actual Apple-server or complete-release
acceptance. No credentials are used.
"""
import argparse
import hashlib
from datetime import datetime, timezone
import ipaddress
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import urllib.request
from uuid import uuid4

REPO = Path(__file__).resolve().parents[2]
CASES = (
    'testControlledLandscapeKeyboard',
    'testChineseControlledLandscapeKeyboard',
    'testControlledRelativePointerViewportFollow',
    'testChineseControlledRelativePointerViewportFollow',
    'testControlledScreenBoundaryGestures',
    'testChineseControlledScreenBoundaryGestures',
    'testControlledToolbarRepeatAndIndividualKeys',
    'testChineseControlledToolbarRepeatAndIndividualKeys',
    'testControlledDictationPreview',
    'testChineseControlledDictationPreview',
    'testControlledDisconnectActions',
    'testChineseControlledDisconnectActions',
    'testControlledHotCorners',
    'testChineseControlledHotCorners',
    'testControlledMobileSessionSelection',
    'testChineseControlledMobileSessionSelection',
    'testControlledFullscreenGestures',
    'testChineseControlledFullscreenGestures',
    'testControlledDisplaySelection',
    'testChineseControlledDisplaySelection',
    'testControlledAppleNativeDisplaySelection',
    'testChineseControlledAppleNativeDisplaySelection',
    'testControlledAppleImageCompression',
    'testChineseControlledAppleImageCompression',
    'testControlledViewportNavigation',
    'testChineseControlledViewportNavigation',
    'testControlledConnectionRecovery',
    'testChineseControlledConnectionRecovery',
    'testReceivedNativeGesturesOnControlledDesktop',
    'testReceivedChineseNativeGesturesOnControlledDesktop',
)
LIBRARY_CASES = (
    'testChineseEnglishSwitchAndPersistence',
    'testChineseTemporaryConnectionErrorAndRecovery',
    'testQuickConnectValidationAndTemporarySession',
    'testChineseQuickConnectValidationAndTemporarySession',
    'testPrimaryScreensOnIPhone',
    'testSyntheticRemoteSession',
    'testKeyboardCustomizationOnNarrowSession',
    'testChineseKeyboardCustomizationOnNarrowSession',
)
CLIPBOARD_CASES = (
    'testControlledSharedClipboard',
    'testChineseControlledSharedClipboard',
    'testControlledAppleClipboard',
    'testChineseControlledAppleClipboard',
)
ACCOUNT_CASES = ('testEnglishMacAccountPrompt', 'testChineseMacAccountPrompt')
URL_CASES = ('testConnectionLinkPreservesQuickConnectDraft',)
TABLET_CASES = ('testIPadPencilGestureSettings', 'testChineseIPadPencilGestureSettings')
KEYBOARD_CASES = ('testControlledSoftwareKeyboardReturn', 'testChineseControlledSoftwareKeyboardReturn',
                  'testControlledConnectionPasswordReturn', 'testChineseControlledConnectionPasswordReturn')
STORAGE_CASES = ('testSavedComputerStorageAndRecovery', 'testChineseSavedComputerStorageAndRecovery')
SUITES = {'controlled': CASES, 'library': LIBRARY_CASES, 'clipboard': CLIPBOARD_CASES,
          'account': ACCOUNT_CASES, 'url': URL_CASES, 'tablet': TABLET_CASES, 'keyboard': KEYBOARD_CASES, 'storage': STORAGE_CASES}


def run(command, log):
    with log.open('x') as output:
        subprocess.run(command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT, check=True)


def run_url_delivery(command, log, simulator, output):
    """Deliver one real system URL only after the test reports its open draft."""
    record = {'triggerObserved': False, 'delivered': False}
    with log.open('x') as stream:
        process = subprocess.Popen(command, cwd=REPO, stdout=stream, stderr=subprocess.STDOUT)
        while process.poll() is None:
            if not record['triggerObserved'] and 'AETHERSCREENS_URL_QA_READY' in log.read_text():
                record['triggerObserved'] = True
                url = 'aetherscreens://connect?host=link-qa.invalid&name=Link%20QA&observe=true'
                with (output / 'url-delivery.log').open('x') as delivery_log:
                    delivery = subprocess.run(['xcrun', 'simctl', 'openurl', simulator, url],
                                              stdout=delivery_log, stderr=subprocess.STDOUT)
                record['deliveryExitCode'] = delivery.returncode
                record['delivered'] = delivery.returncode == 0
            time.sleep(0.1)
        record['testProcessExit'] = process.returncode
    (output / 'url-delivery.json').write_text(json.dumps(record, indent=2) + '\n')
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, command)
    return record


def tcp_port(value):
    port = int(value)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError('TCP port must be between 1 and 65535')
    return port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=tuple(SUITES), default='controlled')
    parser.add_argument('--case', dest='selected_cases', action='append',
                        help='Execute a named case from the selected suite; defaults to the complete suite')
    parser.add_argument('--input-diagnostics', action='store_true',
                        help='Opt in to payload-free input diagnostics and preserve the simulator app snapshot')
    destination_group = parser.add_mutually_exclusive_group(required=True)
    destination_group.add_argument('--simulator-id')
    destination_group.add_argument('--device-id', help='USB-connected physical device UDID')
    parser.add_argument('--development-team', help='Signing team required for a physical device')
    parser.add_argument('--mac-account-host', type=ipaddress.IPv4Address,
                        help='Explicit Mac target for account-prompt validation; dummy credentials are never submitted')
    parser.add_argument('--mac-account-port', default=5900, type=tcp_port)
    parser.add_argument('--fixture-host', default='127.0.0.1', type=ipaddress.IPv4Address)
    parser.add_argument('--rfb-port', type=tcp_port,
                        help='Fixture port; defaults to 6001 for Apple clipboard, otherwise 5999')
    parser.add_argument('--display-rfb-port', default=6000, type=tcp_port)
    parser.add_argument('--native-display-rfb-port', default=6002, type=tcp_port)
    parser.add_argument('--http-port', default=8768, type=tcp_port)
    parser.add_argument('--derived-data', type=Path, default=REPO / 'build/controlled-ui-derived')
    parser.add_argument('--output', type=Path, help='New artifact directory; must not exist')
    args = parser.parse_args()
    if args.input_diagnostics and not args.simulator_id:
        parser.error('Controlled diagnostic snapshot collection requires a simulator')
    if args.rfb_port is None:
        args.rfb_port = 6001 if args.suite == 'clipboard' else 5999
    cases = SUITES[args.suite]
    if args.selected_cases:
        if len(set(args.selected_cases)) != len(args.selected_cases) or any(case not in cases for case in args.selected_cases):
            parser.error('--case must name unique cases from the selected suite')
        cases = tuple(args.selected_cases)
    if args.suite == 'library' and (args.device_id or not args.fixture_host.is_loopback or args.rfb_port != 5999):
        parser.error('Library fixture cases require a simulator and loopback RFB port 5999')
    if args.suite == 'url' and args.device_id:
        parser.error('System URL delivery requires a simulator')
    if args.suite == 'account' and args.mac_account_host is None:
        parser.error('Account prompt cases require --mac-account-host')
    if args.mac_account_host is not None and args.suite != 'account':
        parser.error('--mac-account-host applies only to the account suite')
    if args.device_id and (not args.development_team or
                          (args.suite in ('controlled', 'clipboard', 'keyboard') and args.fixture_host.is_loopback)):
        parser.error('Physical QA requires --development-team and the fixture LAN IPv4 address')
    fixture_host = str(args.fixture_host)
    if args.suite in ('controlled', 'library', 'clipboard', 'keyboard'):
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
    destination = ('platform=iOS Simulator,id=' + args.simulator_id) if is_simulator else ('platform=iOS,arch=arm64,id=' + args.device_id)
    print('Artifacts: ' + str(output), flush=True)
    if is_simulator:
        subprocess.run(['xcrun', 'simctl', 'bootstatus', args.simulator_id, '-b'], check=True)
    signing = ['CODE_SIGNING_ALLOWED=NO'] if is_simulator else ['DEVELOPMENT_TEAM=' + args.development_team]
    run(['xcodebuild', 'build-for-testing', '-project', 'ios/AetherScreensIOS.xcodeproj',
         '-scheme', 'AetherScreensIOS', '-destination', destination,
         '-derivedDataPath', str(derived), *signing], output / 'build.log')
    products = derived / 'Build/Products'
    platform = 'iphonesimulator' if is_simulator else 'iphoneos'
    candidates = list(products.glob('AetherScreensIOS_AetherScreensIOS_' + platform + '*.xctestrun'))
    if not candidates:
        raise RuntimeError('No freshly generated test configuration')
    current = max(candidates, key=lambda path: path.stat().st_mtime)
    configuration = plistlib.loads(current.read_bytes())
    if is_simulator:
        # Xcode can execute a previously installed XCTest runner after replacing
        # its on-disk bundle. Refresh only our runner, preserving app/user data.
        runner = products / 'Debug-iphonesimulator/AetherScreensIOSUITests-Runner.app'
        runner_id = plistlib.loads((runner / 'Info.plist').read_bytes())['CFBundleIdentifier']
        if runner_id != 'com.aethernative.aetherscreens.ios.uitests.xctrunner':
            raise RuntimeError('Unexpected simulator test runner identity')
        installed = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.simulator_id, runner_id],
                                   capture_output=True, text=True)
        (output / 'runner-refresh.log').write_text(installed.stdout + installed.stderr)
        if installed.returncode == 0:
            subprocess.run(['xcrun', 'simctl', 'uninstall', args.simulator_id, runner_id], check=True)
        elif installed.returncode != 2:
            raise RuntimeError('Cannot determine simulator test runner installation; inspect runner-refresh.log')
    for group in configuration['TestConfigurations']:
        for target in group['TestTargets']:
            target.setdefault('EnvironmentVariables', {})['AETHERSCREENS_GESTURE_QA'] = '1'
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_HOST'] = fixture_host
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_RFB_PORT'] = str(args.rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_DISPLAY_PORT'] = str(args.display_rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_NATIVE_DISPLAY_PORT'] = str(args.native_display_rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_HTTP_PORT'] = str(args.http_port)
            if args.input_diagnostics:
                target['EnvironmentVariables']['AETHERSCREENS_INPUT_DIAGNOSTICS_QA'] = '1'
            if args.suite == 'account':
                target['EnvironmentVariables']['AETHERSCREENS_MAC_ONLY_HOST'] = str(args.mac_account_host)
                target['EnvironmentVariables']['AETHERSCREENS_MAC_ONLY_PORT'] = str(args.mac_account_port)
            if args.suite == 'url':
                target['EnvironmentVariables']['AETHERSCREENS_URL_ROUTING_QA'] = '1'
    # Keep __TESTROOT__ valid, use a new path to avoid reusing discovery metadata,
    # and never replace the generated plan or any existing opt-in configuration.
    fresh = products / f'CONTROLLED_GESTURE_{token}.xctestrun'
    with fresh.open('xb') as plan:
        plistlib.dump(configuration, plan)
    result = output / 'result.xcresult'
    command = ['xcodebuild', 'test-without-building', '-xctestrun', str(fresh),
               '-destination', destination, '-derivedDataPath', str(derived),
               '-parallel-testing-enabled', 'NO',
               # Assertion logs/screenshots stay in xcresult; avoid an automatic
               # full simulator sysdiagnose on every failure in a disk-limited VM.
               '-collect-test-diagnostics', 'never',
               *['-only-testing:AetherScreensIOSUITests/AetherScreensIOSUITests/' + case for case in cases]]
    test_error = None
    url_delivery = None
    try:
        enumeration = output / 'enumeration.json'
        run([*command, '-enumerate-tests', '-test-enumeration-style', 'flat',
             '-test-enumeration-format', 'json', '-test-enumeration-output-path', str(enumeration)], output / 'enumeration.log')
        discovered = json.loads(enumeration.read_text())
        enabled = {test['identifier'] for group in discovered.get('values', [])
                   for test in group.get('enabledTests', [])}
        expected_discovery = {'AetherScreensIOSUITests/AetherScreensIOSUITests/' + case + '()' for case in cases}
        if discovered.get('errors') or enabled != expected_discovery:
            raise RuntimeError(f'Controlled test discovery incomplete: missing={sorted(expected_discovery - enabled)}, unexpected={sorted(enabled - expected_discovery)}; inspect {output}')
        try:
            if args.suite == 'url':
                url_delivery = run_url_delivery([*command, '-resultBundlePath', str(result)],
                                                output / 'tests.log', args.simulator_id, output)
            else:
                run([*command, '-resultBundlePath', str(result)], output / 'tests.log')
        except subprocess.CalledProcessError as error:
            if not result.exists():
                raise
            # Failed assertions still produce the authoritative result bundle.
            # Export its inventory and summary before rejecting the gate.
            test_error = error
    finally:
        fresh.unlink()
    reports = {}
    for name in ('summary', 'tests'):
        raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', name, '--path', str(result)], text=True)
        (output / (name + '.json')).write_text(raw)
        reports[name] = json.loads(raw)
    # Screenshots and received wire events belong to the gate, including failures.
    # Never report an accepted UI run without its exported attachments.
    run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
         '--output-path', str(output / 'attachments')], output / 'attachments-export.log')
    if not (output / 'attachments/manifest.json').is_file():
        raise RuntimeError('UI attachment export did not produce a manifest')
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
    if args.input_diagnostics:
        container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator_id,
                                                 'com.aethernative.aetherscreens.ios', 'data'], text=True).strip())
        source = container / 'Library/Caches/AetherScreensInputDiagnostics/input-v1.json'
        payload = source.read_bytes()
        if len(payload) > 32768:
            raise RuntimeError('Input diagnostic snapshot exceeds the bounded schema')
        snapshot = json.loads(payload)
        if set(snapshot) != {'schema', 'records'} or snapshot['schema'] != 1 or not 1 <= len(snapshot['records']) <= 128:
            raise RuntimeError('Unexpected input diagnostic snapshot')
        allowed = {'sequence', 'uptime', 'session', 'stage', 'flags', 'buttons', 'down', 'appleFlags', 'appleCommand'}
        if any(not set(record) <= allowed for record in snapshot['records']):
            raise RuntimeError('Unexpected field in input diagnostic snapshot')
        (output / 'input-diagnostics.json').write_bytes(payload)
        (output / 'input-diagnostics-receipt.json').write_text(json.dumps({
            'SHA256': hashlib.sha256(payload).hexdigest(), 'bytes': len(payload),
            'records': len(snapshot['records']),
            'stages': sorted({record['stage'] for record in snapshot['records']}),
            'transportCompletionIsRemoteExecutionProof': False,
        }, indent=2) + '\n')
    animation_waits = (output / 'tests.log').read_text().count(
        'App animations complete notification not received')
    # A passed assertion after repeated 60-second idle timeouts does not prove
    # reliable UI automation or responsiveness. Retain the functional result,
    # but require diagnosis before accepting this UI gate.
    (output / 'gate.json').write_text(json.dumps({
        'processExit': test_error.returncode if test_error else 0,
        'animationCompletionTimeouts': animation_waits,
        'expectedCases': sorted(expected),
        'actualCases': sorted(actual),
        'systemURLDelivery': url_delivery,
    }, indent=2) + '\n')
    if (test_error is not None or actual != expected or summary.get('totalTestCount') != len(cases)
            or summary.get('passedTests') != len(cases)
            or summary.get('failedTests') != 0 or summary.get('skippedTests') != 0
            or summary.get('runtimeWarnings') != [] or animation_waits
            or (args.suite == 'url' and not (url_delivery and url_delivery['triggerObserved'] and url_delivery['delivered']))):
        raise RuntimeError(f'Controlled QA incomplete: processExit={test_error.returncode if test_error else 0}, animationCompletionTimeouts={animation_waits}, missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}; inspect {output}')
    print(f'PASS: all {len(cases)} requested {args.suite} cases executed, no skips/failures/runtime warnings', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('Controlled QA failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
