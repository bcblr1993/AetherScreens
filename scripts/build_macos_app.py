#!/usr/bin/env python3
"""Build the complete unsigned macOS host and embedded Widget in a new directory.

This entry point never loads signing.local.env, installs, launches, or publishes.
Compiler output stays in memory; only fixed phase/status fields are printed.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys


SOURCE = Path(__file__).resolve().parents[1]
GROUP = 'group.com.aethernative.aetherscreens'


class Rejected(Exception):
    pass


def require(condition, status):
    if not condition:
        raise Rejected(status)


def local_source(relative):
    candidate = SOURCE / 'macos' / relative
    resolved = Path(os.path.abspath(candidate))
    require(resolved.is_relative_to(SOURCE), 'source-path-rejected')
    current = SOURCE
    for part in resolved.relative_to(SOURCE).parts:
        current = current / part
        require(not current.is_symlink(), 'source-path-rejected')
    require(resolved.exists() and resolved.resolve() == resolved, 'source-unavailable')
    return str(resolved)


def copy_cache(seed, destination):
    require(seed.is_dir() and seed.resolve() == seed, 'cache-path-rejected')
    for path in seed.rglob('*'):
        if path.is_symlink():
            require(not os.path.isabs(os.readlink(path)) and path.resolve().is_relative_to(seed),
                    'cache-link-rejected')
        else:
            require(path.is_file() or path.is_dir(), 'cache-entry-rejected')
    shutil.copytree(seed, destination, symlinks=True)
    # Cached checkouts can point at the repository cache from an earlier build.
    # Rebind only our copy; never read, modify or chmod that earlier directory.
    for path in destination.rglob('alternates'):
        require(path.relative_to(destination).parts[:1] == ('checkouts',)
                and path.parts[-4:] == ('.git', 'objects', 'info', 'alternates')
                and path.is_file() and not path.is_symlink(), 'cache-alternates-rejected')
        lines = path.read_text().splitlines()
        require(len(lines) == 1, 'cache-alternates-rejected')
        previous = Path(lines[0])
        require(previous.parts[-3:-2] == ('repositories',) and previous.name == 'objects',
                'cache-alternates-rejected')
        target = destination / 'repositories' / previous.parent.name / 'objects'
        require(target.is_dir() and not target.is_symlink(), 'cache-alternates-rejected')
        metadata = path.lstat()
        require(path.parent.resolve() == path.parent and stat.S_ISREG(metadata.st_mode)
                and metadata.st_uid == os.getuid() and metadata.st_nlink == 1,
                'cache-alternates-rejected')
        path.chmod(stat.S_IMODE(metadata.st_mode) | stat.S_IWUSR)
        path.write_text(str(target) + '\n')


def command(argv, environment, cwd, phase, records):
    print(json.dumps({'phase': phase, 'state': 'running'}), flush=True)
    process = subprocess.Popen(argv, env=environment, cwd=cwd,
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    timeout = False
    try:
        process.communicate(timeout=1800)
    except subprocess.TimeoutExpired:
        timeout = True
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
    record = {'phase': phase, 'state': 'terminal', 'exitCode': process.returncode,
              'timedOut': timeout, 'argvSHA256': hashlib.sha256(
                  json.dumps(argv, separators=(',', ':')).encode()).hexdigest()}
    records.append(record)
    print(json.dumps(record, sort_keys=True), flush=True)
    require(not timeout and process.returncode == 0, phase + '-failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', required=True, type=Path)
    parser.add_argument('--package-cache', type=Path)
    parser.add_argument('--xcodegen', type=Path, default=Path('/opt/homebrew/bin/xcodegen'),
                        help='Absolute path to an existing xcodegen executable.')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--version', default='1.0.0')
    parser.add_argument('--build-number', default='1')
    args = parser.parse_args()
    root = args.build_root
    records = []
    receipt = {'state': 'preflight', 'exitCode': 2, 'commands': records,
               'appsInstalledOrLaunched': False, 'testsExecuted': False,
               'signingPerformed': False, 'notarizationPerformed': False,
               'signingEnvironmentLoaded': False, 'runtimeAcceptance': False,
               'rawOutputPersisted': False}
    created = False
    try:
        require(re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', args.version) is not None
                and re.fullmatch(r'[1-9][0-9]*', args.build_number) is not None,
                'version-rejected')
        require(root.is_absolute() and root.resolve() == root and not os.path.lexists(root),
                'output-path-rejected')
        require(root.parent.is_dir() and root.parent.resolve() == root.parent,
                'output-parent-rejected')
        require(not args.offline or args.package_cache is not None, 'offline-cache-required')
        require(args.xcodegen.is_absolute(), 'generator-path-rejected')
        generator = args.xcodegen.resolve()
        require(generator.is_file() and stat.S_ISREG(generator.stat().st_mode)
                and os.access(generator, os.X_OK), 'generator-executable-rejected')
        receipt['generatorSHA256'] = hashlib.sha256(generator.read_bytes()).hexdigest()
        specification = json.loads((SOURCE / 'macos/release-project.json').read_text())
        require(specification['name'] == 'AetherScreensMacRelease'
                and set(specification['targets']) == {'AetherScreens', 'AetherScreensWidgets'},
                'release-specification-rejected')
        root.mkdir(mode=0o700)
        created = True
        for name in ['home', 'tmp', 'project', 'DerivedData']:
            (root / name).mkdir()
        environment = {'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
                       'HOME': str(root / 'home'), 'TMPDIR': str(root / 'tmp') + '/',
                       'USER': 'chenxu', 'LOGNAME': 'chenxu', 'TERM': 'dumb',
                       'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
                       'OS_LOG_DISABLED': 'YES', 'PYTHONDONTWRITEBYTECODE': '1',
                       'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
        specification = copy.deepcopy(specification)
        specification['packages']['AetherScreens']['path'] = str(SOURCE)
        for target in specification['targets'].values():
            for item in target['sources']:
                item['path'] = local_source(item['path'])
            target['settings']['base']['CODE_SIGN_ENTITLEMENTS'] = local_source(
                target['settings']['base']['CODE_SIGN_ENTITLEMENTS'])
            target['info']['path'] = str(root / 'project' / Path(target['info']['path']).name)
            require(target['info']['properties']['AetherScreensWidgetGroupIdentifier'] == GROUP,
                    'release-group-rejected')
        generated_spec = root / 'project/release-project.json'
        generated_spec.write_text(json.dumps(specification, sort_keys=True, indent=2) + '\n')
        packages = root / 'DerivedData/SourcePackages'
        if args.package_cache is not None:
            copy_cache(args.package_cache, packages)
        command([str(generator), 'generate', '--spec', str(generated_spec)],
                environment, root / 'project', 'generate', records)
        project = root / 'project/AetherScreensMacRelease.xcodeproj'
        pins = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        pins.parent.mkdir(parents=True, exist_ok=True)
        require(not os.path.lexists(pins), 'generated-pins-exist')
        with pins.open('xb') as stream:
            stream.write((SOURCE / 'Package.resolved').read_bytes())
        # SwiftPM reads .netrc through Foundation's home directory, not just HOME.
        # Pin only xcodebuild to our empty credential file; keep generator env intact.
        netrc = root / 'home/.netrc'
        with netrc.open('xb'):
            pass
        netrc.chmod(0o600)
        build_environment = dict(environment, CFFIXED_USER_HOME=environment['HOME'])
        argv = ['/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild', 'build',
                '-project', str(project), '-scheme', 'AetherScreens', '-configuration', 'Release',
                '-destination', 'generic/platform=macOS', '-derivedDataPath', str(root / 'DerivedData'),
                '-clonedSourcePackagesDirPath', str(packages),
                '-packageAuthorizationProvider', 'netrc',
                '-onlyUsePackageVersionsFromResolvedFile', 'CODE_SIGNING_ALLOWED=NO',
                'CODE_SIGNING_REQUIRED=NO', 'MARKETING_VERSION=' + args.version,
                'CURRENT_PROJECT_VERSION=' + args.build_number, 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES']
        if args.offline:
            argv.extend(['-disableAutomaticPackageResolution', '-skipPackageUpdates'])
        command(argv, build_environment, root / 'project', 'build', records)
        app = root / 'DerivedData/Build/Products/Release/AetherScreens.app'
        require(app.is_dir() and not app.is_symlink()
                and (app / 'Contents/PlugIns/AetherScreensWidgets.appex').is_dir(),
                'embedded-widget-unavailable')
        receipt.update(state='unsigned-native-host-and-widget-compiled', exitCode=0,
                       application=str(app), version=args.version, buildNumber=args.build_number)
    except Rejected as failure:
        receipt['state'] = str(failure)
    except Exception:
        receipt['state'] = 'build-driver-error'
    if created:
        with (root / 'build-receipt.json').open('x') as stream:
            json.dump(receipt, stream, sort_keys=True, indent=2)
            stream.write('\n')
    print(json.dumps({'state': receipt['state'], 'exitCode': receipt['exitCode']}, sort_keys=True))
    return receipt['exitCode']


if __name__ == '__main__':
    sys.exit(main())
