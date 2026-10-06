"""Explicit-target Mac clipboard gate; no credentials in arguments or environment.

Uses the application's noninteractive saved Keychain credential and existing SSH
authorization. The remote helper restores clipboard data in memory and is
removed after the selected native test, including failed tests.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True)
    parser.add_argument('--account', required=True)
    parser.add_argument('--rich', action='store_true')
    parser.add_argument('--apple-push-frames', action='store_true', help='Verify clipboard/frame compatibility with Apple server-driven updates')
    parser.add_argument('--log', required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', args.host):
        parser.error('Invalid explicit host')
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*', args.account):
        parser.error('Invalid SSH account')
    root = Path(__file__).resolve().parents[2]
    helper = root / 'scripts/qa/clipboard_copy_fixture.swift'
    test = root / 'Tests/AetherScreensCoreTests/LiveFunctionalTests.swift'
    log_path = args.log.resolve()
    verification_path = log_path.with_suffix('.verification.json')
    if verification_path.exists():
        parser.error('The verification file already exists; choose a fresh log path')
    log_path.parent.mkdir(parents=True, exist_ok=True)
    ssh_options = ['-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5']
    destination = args.account + '@' + args.host
    ssh = ['ssh', *ssh_options, destination]
    result = {'target': args.host, 'rich': args.rich, 'applePushFrames': args.apple_push_frames, 'passed': False,
              'remoteHelperRemoved': False,
              'testSourceSHA256': hashlib.sha256(test.read_bytes()).hexdigest(),
              'helperSourceSHA256': hashlib.sha256(helper.read_bytes()).hexdigest()}
    # Exclusive creation prevents an accidental replacement of earlier evidence.
    with log_path.open('x') as log:
        directory = subprocess.check_output(
            ssh + ['mktemp -d /tmp/aetherscreens-clipboard.XXXXXXXX'], text=True).strip()
        if not re.fullmatch(r'/tmp/aetherscreens-clipboard\.[A-Za-z0-9]+', directory):
            raise RuntimeError('Unexpected remote temporary directory')
        try:
            subprocess.run(['scp', '-q', *ssh_options, str(helper),
                            destination + ':' + directory + '/fixture.swift'], check=True)
            digest = subprocess.check_output(
                ssh + ['shasum -a 256 ' + directory + '/fixture.swift'], text=True).split()[0]
            if digest != result['helperSourceSHA256']:
                raise RuntimeError('Remote helper source hash mismatch')
            env = dict(os.environ, AETHERSCREENS_QA_CLIPBOARD_COMPATIBILITY='1',
                       AETHERSCREENS_LIVE_HOST=args.host,
                       AETHERSCREENS_QA_REMOTE_CLIPBOARD_FIXTURE=directory + '/fixture.swift')
            env.pop('AETHERSCREENS_LIVE_PASSWORD', None)
            env.pop('AETHERSCREENS_QA_RICH_CLIPBOARD', None)
            env.pop('AETHERSCREENS_QA_APPLE_PUSH_FRAMES', None)
            if args.rich:
                env['AETHERSCREENS_QA_RICH_CLIPBOARD'] = '1'
            if args.apple_push_frames:
                env['AETHERSCREENS_QA_APPLE_PUSH_FRAMES'] = '1'
            run = subprocess.run(
                ['swift', 'test', '-c', 'release', '--filter',
                 'LiveFunctionalTests.testLiveAppleClipboardMonitoringAndManualFetchCompatibility'],
                cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
            result['testExitCode'] = run.returncode
        finally:
            subprocess.run(ssh + ['rm -f ' + directory + '/fixture.swift && rmdir ' + directory], check=True)
            result['remoteHelperRemoved'] = True
    text = log_path.read_text()
    result['logSHA256'] = hashlib.sha256(log_path.read_bytes()).hexdigest()
    result['passed'] = result.get('testExitCode') == 0 and bool(re.search(
        r"Test Case .*testLiveAppleClipboardMonitoringAndManualFetchCompatibility.* passed \(", text))
    result['skipped'] = bool(re.search(
        r"Test Case .*testLiveAppleClipboardMonitoringAndManualFetchCompatibility.* skipped", text))
    result['passed'] = result['passed'] and not result['skipped']
    with verification_path.open('x') as verification:
        verification.write(json.dumps(result, indent=2))
    print(json.dumps(result))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
