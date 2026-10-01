#!/usr/bin/env python3
"""Run the ten controlled iOS display/gesture/recovery scenarios and reject omissions.

Start gesture_rfb_fixture.py separately. This is a simulator sub-gate, not
physical-device or complete-release acceptance. No credentials are used.
"""
import argparse
from datetime import datetime, timezone
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator-id', required=True)
    parser.add_argument('--derived-data', type=Path, default=REPO / 'build/controlled-ui-derived')
    parser.add_argument('--output', type=Path, help='New artifact directory; must not exist')
    args = parser.parse_args()
    try:
        with urllib.request.urlopen('http://127.0.0.1:8768/events', timeout=2) as response:
            if not isinstance(json.load(response), list):
                parser.error('Unexpected controlled fixture response')
    except (OSError, ValueError) as error:
        parser.error('Start scripts/qa/gesture_rfb_fixture.py first: ' + str(error))
    token = uuid4().hex
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = (args.output or REPO / f'build/controlled-gesture-{stamp}-{token[:8]}').resolve()
    output.mkdir(parents=True, exist_ok=False)
    derived = args.derived_data.resolve()
    destination = 'platform=iOS Simulator,id=' + args.simulator_id
    print('Artifacts: ' + str(output), flush=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', args.simulator_id, '-b'], check=True)
    run(['xcodebuild', 'build-for-testing', '-project', 'ios/AetherScreensIOS.xcodeproj',
         '-scheme', 'AetherScreensIOS', '-destination', destination,
         '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO'], output / 'build.log')
    products = derived / 'Build/Products'
    candidates = list(products.glob('AetherScreensIOS_AetherScreensIOS_iphonesimulator*.xctestrun'))
    if not candidates:
        raise RuntimeError('No freshly generated simulator test configuration')
    current = max(candidates, key=lambda path: path.stat().st_mtime)
    configuration = plistlib.loads(current.read_bytes())
    for group in configuration['TestConfigurations']:
        for target in group['TestTargets']:
            target.setdefault('EnvironmentVariables', {})['AETHERSCREENS_GESTURE_QA'] = '1'
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
