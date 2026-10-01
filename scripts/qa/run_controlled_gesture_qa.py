#!/usr/bin/env python3
"""Run the ten controlled iOS display/gesture/recovery scenarios and reject omissions.

Start gesture_rfb_fixture.py separately. This is a controlled
simulator/physical-input sub-gate, not actual Apple-server or complete-release
acceptance. No credentials are used.
"""
import argparse
from datetime import datetime, timezone
import ipaddress
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import urllib.request
from uuid import uuid4

REPO = Path(__file__).resolve().parents[2]
CASES = (
    'testControlledFullscreenGestures',
    'testChineseControlledFullscreenGestures',
    'testControlledDisplaySelection',
    'testChineseControlledDisplaySelection',
    'testControlledViewportNavigation',
    'testChineseControlledViewportNavigation',
    'testControlledConnectionRecovery',
    'testChineseControlledConnectionRecovery',
    'testReceivedNativeGesturesOnControlledDesktop',
    'testReceivedChineseNativeGesturesOnControlledDesktop',
)


def run(command, log):
    with log.open('x') as output:
        subprocess.run(command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT, check=True)


def tcp_port(value):
    port = int(value)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError('TCP port must be between 1 and 65535')
    return port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    destination_group = parser.add_mutually_exclusive_group(required=True)
    destination_group.add_argument('--simulator-id')
    destination_group.add_argument('--device-id', help='USB-connected physical device UDID')
    parser.add_argument('--development-team', help='Signing team required for a physical device')
    parser.add_argument('--fixture-host', default='127.0.0.1', type=ipaddress.IPv4Address)
    parser.add_argument('--rfb-port', default=5999, type=tcp_port)
    parser.add_argument('--display-rfb-port', default=6000, type=tcp_port)
    parser.add_argument('--http-port', default=8768, type=tcp_port)
    parser.add_argument('--derived-data', type=Path, default=REPO / 'build/controlled-ui-derived')
    parser.add_argument('--output', type=Path, help='New artifact directory; must not exist')
    args = parser.parse_args()
    if args.device_id and (not args.development_team or args.fixture_host.is_loopback):
        parser.error('Physical QA requires --development-team and the fixture LAN IPv4 address')
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
    for group in configuration['TestConfigurations']:
        for target in group['TestTargets']:
            target.setdefault('EnvironmentVariables', {})['AETHERSCREENS_GESTURE_QA'] = '1'
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_HOST'] = fixture_host
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_RFB_PORT'] = str(args.rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_DISPLAY_PORT'] = str(args.display_rfb_port)
            target['EnvironmentVariables']['AETHERSCREENS_GESTURE_HTTP_PORT'] = str(args.http_port)
    # Keep __TESTROOT__ valid, use a new path to avoid reusing discovery metadata,
    # and never replace the generated plan or any existing opt-in configuration.
    fresh = products / f'CONTROLLED_GESTURE_{token}.xctestrun'
    with fresh.open('xb') as plan:
        plistlib.dump(configuration, plan)
    result = output / 'result.xcresult'
    command = ['xcodebuild', 'test-without-building', '-xctestrun', str(fresh),
               '-destination', destination, '-parallel-testing-enabled', 'NO',
               *['-only-testing:AetherScreensIOSUITests/AetherScreensIOSUITests/' + case for case in CASES]]
    try:
        enumeration = output / 'enumeration.json'
        run([*command, '-enumerate-tests', '-test-enumeration-style', 'flat',
             '-test-enumeration-format', 'json', '-test-enumeration-output-path', str(enumeration)], output / 'enumeration.log')
        discovered = json.loads(enumeration.read_text())
        enabled = {test['identifier'] for group in discovered.get('values', [])
                   for test in group.get('enabledTests', [])}
        expected_discovery = {'AetherScreensIOSUITests/AetherScreensIOSUITests/' + case + '()' for case in CASES}
        if discovered.get('errors') or enabled != expected_discovery:
            raise RuntimeError(f'Controlled test discovery incomplete: missing={sorted(expected_discovery - enabled)}, unexpected={sorted(enabled - expected_discovery)}; inspect {output}')
        run([*command, '-resultBundlePath', str(result)], output / 'tests.log')
    finally:
        fresh.unlink()
    reports = {}
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
    expected = {'AetherScreensIOSUITests/' + case + '()' for case in CASES}
    summary = reports['summary']
    if (actual != expected or summary.get('totalTestCount') != len(CASES)
            or summary.get('passedTests') != len(CASES)
            or summary.get('failedTests') != 0 or summary.get('skippedTests') != 0
            or summary.get('runtimeWarnings') != []):
        raise RuntimeError(f'Controlled QA incomplete: missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}; inspect {output}')
    print(f'PASS: all {len(CASES)} requested cases executed, no skips/failures/runtime warnings', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('Controlled QA failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
