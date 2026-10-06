#!/usr/bin/env python3
"""One explicitly started, bounded headless QA round on chenxu's Macmini.

The caller stages source.tgz and a {relativePath: SHA256} source-manifest.json
in the fixed ROOT/staged directory, and 32 pinned XcodeGen files in toolchain.
No path override, cleanup, installation, GUI, signing, or account access exists.
An existing current directory is a hard stop: use the separately reviewed
ownership/closure cleanup tool before starting the next round.

mac-build invokes the staged scripts/build_macos_app.py entry point. Its command
hook is supervised here so budget checks also cover its compiler children and
compiler output can be reduced before it leaves memory. core-tests additionally
requires --authorize-core-tests and --core-isolation-sha256; see review_pin().
protocol-tests uses the same explicit review, copies five pinned production
protocol files and two original XCTest files into a dependency-free target,
and reports only subset acceptance. It cannot satisfy the full package gate.
package-graph requires its own authorization and source/seed review pin. It only
loads package manifests and the dependency graph, without product or test builds.
ios-compile builds only the generic iOS Simulator destination, without launching
a simulator or invoking tests. Compile success is not runtime/UI acceptance.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import time


ROOT = Path('/Users/chenxu/aetherscreens-first-release-qa')
CURRENT = ROOT / 'current'
STAGED = ROOT / 'staged'
TOOLCHAIN = ROOT / 'toolchain'
DEPENDENCY_INPUTS = ROOT / 'dependency-inputs'
DEPENDENCY_MANIFEST = DEPENDENCY_INPUTS / 'seed-manifest.json'
DEPENDENCY_LOCK_SHA = '873816bd67aff0f1e96c940f830455a1df6d98129a6e78bda8c2c6aaa4d04d01'
MAX_SEED_BYTES = 1024 ** 3
MAX_SEED_FILES = 4096
SEED_METADATA_DIRECTORIES = {'preparation-home', 'preparation-tmp', 'empty-template'}
GENERATOR = TOOLCHAIN / 'bin/xcodegen'
OWNER = ROOT / '.aetherscreens-headless-owner.json'
ROUND_OWNER = '.aetherscreens-artifact-owner.json'
DEVELOPER = Path('/Applications/Xcode.app/Contents/Developer')
XCODEBUILD = DEVELOPER / 'usr/bin/xcodebuild'
SWIFT = DEVELOPER / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift'
GENERATOR_SHA = '5b5d393779d405bbe78a2de8130f0bfaa4f90f7295cd3c8436d620b04aaee49a'
TOOLCHAIN_MANIFEST_SHA = '2e89ca784e785f19c6dc276d817defc545f2b50dbc073dac89da0cf0dafc083b'
MAX_BYTES = 24 * 1024 ** 3
MIN_FREE = 8 * 1024 ** 3
MAX_INPUT = 256 * 1024 ** 2
MAX_UNPACKED = 512 * 1024 ** 2
MAX_OUTPUT = 16 * 1024 ** 2
QUERY_ENV = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C',
             'PYTHONDONTWRITEBYTECODE': '1'}
DEPENDENCY_IDENTITIES = {
    'https://github.com/attaswift/BigInt.git': 'bigint',
    'https://github.com/orlandos-nl/Citadel.git': 'citadel',
    'https://github.com/apple/swift-asn1.git': 'swift-asn1',
    'https://github.com/apple/swift-atomics.git': 'swift-atomics',
    'https://github.com/apple/swift-collections.git': 'swift-collections',
    'https://github.com/apple/swift-crypto.git': 'swift-crypto',
    'https://github.com/apple/swift-log.git': 'swift-log',
    'https://github.com/apple/swift-nio.git': 'swift-nio',
    'https://github.com/Wellz26/swift-nio-ssh.git': 'swift-nio-ssh',
    'https://github.com/apple/swift-system.git': 'swift-system',
}


class Rejected(Exception):
    pass


def require(value, case):
    if not value:
        raise Rejected(case)


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate-json-key')
        result[key] = value
    return result


def hash_value(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def safe_path(path, exists=True):
    require(path.is_absolute() and os.path.abspath(path) == str(path), 'unsafe-path')
    for part in reversed([path] + list(path.parents)):
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode), 'symlink-path')
    require(path.resolve() == path and (not exists or path.exists()), 'unsafe-path')
    return path


def file_hash(path, maximum=MAX_INPUT):
    safe_path(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= maximum, 'unsafe-file')
        digest = hashlib.sha256()
        with os.fdopen(os.dup(descriptor), 'rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        after = os.fstat(descriptor)
        require((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                 before.st_ctime_ns) ==
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns,
                 after.st_ctime_ns), 'file-changed-during-hash')
        return digest.hexdigest()
    finally:
        os.close(descriptor)


def pinned_json(path, expected, maximum=16 * 1024 ** 2):
    require(hash_value(expected) and file_hash(path, maximum) == expected, 'input-hash-mismatch')
    raw = path.read_bytes()
    require(len(raw) <= maximum and sha(raw) == expected and file_hash(path, maximum) == expected,
            'input-hash-mismatch')
    try:
        return json.loads(raw, object_pairs_hook=unique)
    except (ValueError, UnicodeError):
        raise Rejected('invalid-json')


def relative_name(value):
    require(isinstance(value, str) and value and not any(ord(c) < 32 for c in value),
            'unsafe-relative-name')
    path = Path(value)
    require(not path.is_absolute() and path.as_posix() == value and
            all(part not in ('', '.', '..') for part in path.parts), 'unsafe-relative-name')
    return path


def validate_manifest(manifest, toolchain=False):
    require(isinstance(manifest, dict) and 1 <= len(manifest) <= 50000, 'manifest-schema')
    for name, digest in manifest.items():
        path = relative_name(name)
        require(hash_value(digest), 'manifest-hash-schema')
        if toolchain:
            require(name == 'bin/xcodegen' or name.startswith('share/xcodegen/SettingPresets/'),
                    'toolchain-file-rejected')
        else:
            workflow = (len(path.parts) == 3 and path.parts[:2] == ('.github', 'workflows')
                        and not path.name.startswith('.') and path.suffix in ('.yml', '.yaml'))
            hidden_exception = name == '.gitignore' or workflow
            require(path.parts[0] in ('Sources', 'Tests', 'assets', 'ios', 'macos',
                                     'scripts', 'docs', 'Package.swift', 'Package.resolved',
                                     'README.md', 'LICENSE', 'LICENSE.md', 'website_content') or
                    name in ('AppIcon.icns', 'AppIcon_1024.png') or hidden_exception,
                    'source-file-rejected')
            require((not any(p.startswith('.') for p in path.parts) or hidden_exception) and
                    path.suffix.lower() not in ('.p12', '.pem', '.key', '.mobileprovision',
                                               '.sqlite', '.db', '.env') and
                    path.name != 'signing.local.env', 'private-input-rejected')
    if toolchain:
        require(len(manifest) == 32 and manifest.get('bin/xcodegen') == GENERATOR_SHA,
                'toolchain-set-rejected')
    else:
        require({'Package.swift', 'Package.resolved', 'scripts/build_macos_app.py',
                 'macos/release-project.json', 'ios/project.yml'} <= set(manifest),
                'source-entrypoints-unavailable')


def verify_tree(directory, manifest, ignored=()):
    safe_path(directory)
    actual = set()
    for parent, directories, files in os.walk(directory, followlinks=False):
        for name in directories + files:
            path = Path(parent) / name
            require(not path.is_symlink(), 'input-tree-symlink')
        for name in files:
            path = Path(parent) / name
            relative = path.relative_to(directory).as_posix()
            if relative in ignored:
                continue
            require(relative in manifest and file_hash(path) == manifest[relative],
                    'input-tree-hash-mismatch')
            actual.add(relative)
    require(actual == set(manifest), 'input-tree-set-mismatch')
    return sha(encoded(manifest))


def dependency_pins(source):
    lock = pinned_json(source / 'Package.resolved', DEPENDENCY_LOCK_SHA)
    require(isinstance(lock, dict) and set(lock) == {'pins', 'version'} and
            lock['version'] == 2 and isinstance(lock['pins'], list) and len(lock['pins']) == 10,
            'dependency-lock-schema')
    pins = {}
    for pin in lock['pins']:
        require(isinstance(pin, dict) and set(pin) == {'identity', 'kind', 'location', 'state'} and
                DEPENDENCY_IDENTITIES.get(pin['location']) == pin['identity'] and
                pin['kind'] == 'remoteSourceControl' and isinstance(pin['state'], dict) and
                set(pin['state']) == {'version', 'revision'} and
                re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', pin['state']['version']) is not None and
                re.fullmatch('[0-9a-f]{40}', pin['state']['revision']) is not None and
                pin['identity'] not in pins, 'dependency-lock-pin')
        pins[pin['identity']] = pin
    require(set(pins) == set(DEPENDENCY_IDENTITIES.values()), 'dependency-lock-set')
    return pins


def seed_inventory(directory):
    """Hash only bounded, self-contained Git input files; never follow links."""
    safe_path(directory)
    require(directory.is_dir() and directory.lstat().st_uid == os.getuid(), 'seed-root-owner')
    files, directories, size = {}, [], 0
    allocated = directory.lstat().st_blocks * 512
    for parent, child_dirs, names in os.walk(directory, followlinks=False):
        for name in sorted(child_dirs + names):
            path = Path(parent) / name
            info = path.lstat()
            relative = path.relative_to(directory).as_posix()
            require(info.st_uid == os.getuid() and info.st_dev == directory.stat().st_dev and
                    (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)), 'seed-entry-type')
            allocated += info.st_blocks * 512
            require(allocated <= MAX_SEED_BYTES, 'seed-slot-byte-budget')
            if stat.S_ISDIR(info.st_mode):
                directories.append(relative)
                require(len(directories) <= MAX_SEED_FILES, 'seed-directory-budget')
                require(relative in ('objects', 'objects/info', 'objects/pack', 'refs',
                                     'refs/heads', 'refs/tags', 'info') or
                        re.fullmatch('objects/[0-9a-f]{2}', relative) is not None,
                        'seed-directory-rejected')
                continue
            require(info.st_nlink == 1 and
                    (relative in ('HEAD', 'config', 'packed-refs', 'shallow', 'description',
                                  'info/refs', 'objects/info/packs') or
                     re.fullmatch(r'objects/[0-9a-f]{2}/[0-9a-f]{38}', relative) is not None or
                     re.fullmatch(r'objects/pack/pack-[0-9a-f]{40}\.(?:pack|idx|rev)', relative)
                     is not None or
                     re.fullmatch(r'refs/tags/v?[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?',
                                  relative) is not None), 'seed-file-rejected')
            size += info.st_size
            require(size <= MAX_SEED_BYTES and len(files) < MAX_SEED_FILES,
                    'seed-slot-content-budget')
            files[relative] = {'sha256': file_hash(path, MAX_SEED_BYTES), 'size': info.st_size}
    return {'files': files, 'directories': sorted(directories), 'contentBytes': size,
            'allocatedBytes': allocated, 'fileCount': len(files)}


def verify_dependency_seeds(source, expected):
    pins = dependency_pins(source)
    manifest = pinned_json(DEPENDENCY_MANIFEST, expected, 1024 ** 2)
    require(isinstance(manifest, dict) and set(manifest) == {
        'schema', 'purpose', 'root', 'ownerUID', 'packageResolvedSHA256', 'preparerSHA256',
        'workerSHA256', 'sourceManifestSHA256', 'sourceArchiveSHA256', 'repositories',
        'maximumBytes', 'maximumFiles', 'metadataDirectories'} and manifest['schema'] == 1 and
        manifest['purpose'] == 'aetherscreens-pinned-git-inputs' and
        manifest['root'] == str(DEPENDENCY_INPUTS) and manifest['ownerUID'] == os.getuid() and
        manifest['packageResolvedSHA256'] == DEPENDENCY_LOCK_SHA and
        manifest['maximumBytes'] == MAX_SEED_BYTES and manifest['maximumFiles'] == MAX_SEED_FILES and
        manifest['metadataDirectories'] == sorted(SEED_METADATA_DIRECTORIES) and
        all(hash_value(manifest[name]) for name in ('preparerSHA256', 'workerSHA256',
            'sourceManifestSHA256', 'sourceArchiveSHA256')) and
        isinstance(manifest['repositories'], dict) and set(manifest['repositories']) == set(pins),
        'dependency-seed-manifest-schema')
    safe_path(DEPENDENCY_INPUTS)
    require(set(os.listdir(DEPENDENCY_INPUTS)) == {identity + '.git' for identity in pins} |
            SEED_METADATA_DIRECTORIES | {ROUND_OWNER, 'seed-manifest.json', 'prepare-receipt.json'},
            'dependency-input-root-set')
    for name in SEED_METADATA_DIRECTORIES:
        path = safe_path(DEPENDENCY_INPUTS / name)
        require(path.is_dir() and path.stat().st_uid == os.getuid() and not os.listdir(path),
                'dependency-metadata-not-empty')
    total_files, total_bytes = 0, 0
    for identity, pin in pins.items():
        record = manifest['repositories'][identity]
        require(isinstance(record, dict) and set(record) == {
            'originalURL', 'identity', 'version', 'revision', 'tag', 'tagObject', 'tree', 'inventory'}
            and record['originalURL'] == pin['location'] and record['identity'] == identity and
            record['version'] == pin['state']['version'] and
            record['revision'] == pin['state']['revision'] and
            record['tag'] in (record['version'], 'v' + record['version']) and
            re.fullmatch('[0-9a-f]{40}', record['tagObject']) is not None and
            re.fullmatch('[0-9a-f]{40}', record['tree']) is not None, 'dependency-seed-pin-mismatch')
        actual = seed_inventory(DEPENDENCY_INPUTS / (identity + '.git'))
        require(actual == record['inventory'], 'dependency-seed-content-changed')
        total_files += actual['fileCount']
        total_bytes += actual['contentBytes']
    metadata_bytes = sum((DEPENDENCY_INPUTS / name).lstat().st_size for name in
                         (ROUND_OWNER, 'seed-manifest.json', 'prepare-receipt.json'))
    require(total_files + 3 <= MAX_SEED_FILES and total_bytes + metadata_bytes <= MAX_SEED_BYTES and
            allocated_bytes(DEPENDENCY_INPUTS) <= MAX_SEED_BYTES,
            'dependency-input-total-budget')
    owner_path = DEPENDENCY_INPUTS / ROUND_OWNER
    owner = pinned_json(owner_path, file_hash(owner_path), 128 * 1024)
    receipt_path = DEPENDENCY_INPUTS / 'prepare-receipt.json'
    require(owner == {'schema': 1, 'purpose': 'aetherscreens-qa-artifacts',
        'ownerUID': os.getuid(), 'root': str(DEPENDENCY_INPUTS), 'repository': str(source),
        'closed': True, 'evidence': [{'path': str(receipt_path), 'sha256': file_hash(receipt_path)}]},
        'dependency-input-ownership')
    receipt = pinned_json(receipt_path, owner['evidence'][0]['sha256'], 128 * 1024)
    require(receipt.get('state') == 'dependency-inputs-ready' and receipt.get('exitCode') == 0 and
            receipt.get('manifestSHA256') == expected and receipt.get('allTenGitInputsVerified') is True
            and receipt.get('ownedNetworkListeners') == 0, 'dependency-input-not-ready')
    return {'manifestSHA256': expected, 'packageResolvedSHA256': DEPENDENCY_LOCK_SHA,
            'ownershipSHA256': file_hash(owner_path), 'receiptSHA256': file_hash(receipt_path),
            'repositoryCount': 10, 'fileCount': total_files, 'contentBytes': total_bytes,
            'allocatedBytes': allocated_bytes(DEPENDENCY_INPUTS), 'transport': 'file',
            'completeNetworkIsolationProven': False}


def extract_source(archive, source, manifest):
    seen = set()
    total = 0
    with tarfile.open(archive, 'r:gz') as package:
        members = package.getmembers()
        require(len(members) <= 100000, 'archive-entry-budget')
        for item in members:
            name = item.name.rstrip('/') if item.isdir() else item.name
            relative = relative_name(name)
            require(name not in seen and (item.isdir() or item.isfile()), 'archive-entry-rejected')
            seen.add(name)
            require(item.mode & 0o7000 == 0, 'archive-mode-rejected')
            if item.isfile():
                require(name in manifest and 0 <= item.size <= MAX_INPUT, 'archive-file-rejected')
                total += item.size
        require(total <= MAX_UNPACKED and
                {m.name for m in members if m.isfile()} == set(manifest), 'archive-set-mismatch')
        source.mkdir(mode=0o700)
        for item in members:
            if not item.isfile():
                continue
            target = source / relative_name(item.name)
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            contents = package.extractfile(item)
            require(contents is not None, 'archive-data-unavailable')
            with contents, target.open('xb') as output:
                shutil.copyfileobj(contents, output, 1024 * 1024)
            target.chmod(0o600)
    return verify_tree(source, manifest)


def tree_fingerprint(directory):
    """No-follow metadata seal, including every entry and link target, not contents."""
    records = []
    allocated = directory.lstat().st_blocks * 512
    for parent, directories, files in os.walk(directory, followlinks=False):
        for name in sorted(directories + files):
            path = Path(parent) / name
            info = path.lstat()
            require(info.st_uid == os.getuid() and
                    (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode) or
                     stat.S_ISLNK(info.st_mode)), 'output-entry-rejected')
            allocated += info.st_blocks * 512
            target = os.readlink(path) if stat.S_ISLNK(info.st_mode) else ''
            records.append([path.relative_to(directory).as_posix(), info.st_dev, info.st_ino,
                            info.st_mode, info.st_nlink, info.st_size, info.st_mtime_ns,
                            info.st_ctime_ns, info.st_blocks, target])
    records.sort(key=lambda item: item[0])
    return {'treeSHA256': sha(encoded(records)), 'treeHashKind': 'nofollow-metadata-v1',
            'entryCount': len(records), 'allocatedBytes': allocated}


def allocated_bytes(directory):
    """An active-tree budget sample: lstat only; a concurrent unlink is harmless."""
    total = directory.lstat().st_blocks * 512
    for parent, directories, files in os.walk(directory, followlinks=False):
        for name in directories + files:
            try:
                info = (Path(parent) / name).lstat()
            except FileNotFoundError:
                continue
            require(info.st_uid == os.getuid(), 'output-owner-mismatch')
            total += info.st_blocks * 512
    return total


def budget():
    values = {'allocatedBytes': allocated_bytes(ROOT)}
    values['freeBytes'] = shutil.disk_usage(ROOT).free
    require(values['allocatedBytes'] <= MAX_BYTES, 'allocated-budget-exceeded')
    require(values['freeBytes'] >= MIN_FREE, 'free-space-budget-exceeded')
    return values


def query(argv, accepted=(0,)):
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=QUERY_ENV, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        raise Rejected('host-query-unavailable')
    require(result.returncode in accepted, 'host-query-failed')
    return result.stdout


def host_preflight():
    require(sys.platform == 'darwin' and os.getuid() == 501, 'macmini-user-required')
    require(query(['/usr/bin/id', '-un']).strip() == b'chenxu', 'macmini-user-required')
    require(re.search(rb'\binet 192\.168\.50\.226\b', query(['/sbin/ifconfig'])) is not None,
            'macmini-address-required')
    require(query(['/usr/bin/sw_vers', '-productVersion']).strip() == b'27.0.1',
            'macos-version-mismatch')
    for sdk in ('macosx', 'iphonesimulator'):
        result = subprocess.run(['/usr/bin/xcrun', '--sdk', sdk, '--show-sdk-version'],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                                env=dict(QUERY_ENV, DEVELOPER_DIR=str(DEVELOPER)), timeout=15)
        require(result.returncode == 0 and result.stdout.strip() == b'26.5', 'sdk-version-mismatch')


@contextmanager
def exclusive():
    path = ROOT / '.headless-worker.lock'
    safe_path(path, exists=False)
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and
                info.st_nlink == 1, 'unsafe-lock')
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Rejected('worker-already-running')
        yield
    finally:
        os.close(descriptor)


def process_table():
    process = subprocess.Popen(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,lstart=,command='],
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=QUERY_ENV)
    try:
        raw, error = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        raise Rejected('process-inventory-unavailable')
    require(process.returncode == 0 and not error.strip(), 'process-inventory-unavailable')
    records = {}
    for line in raw.decode(errors='replace').splitlines():
        match = re.match(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\w+\s+\w+\s+\d+\s+' +
                         r'\d+:\d+:\d+\s+\d+)\s+(.*)$', line)
        if match:
            pid, ppid, pgid = map(int, match.group(1, 2, 3))
            if pid == process.pid:
                continue
            records[pid] = {'pid': pid, 'parentPID': ppid, 'processGroup': pgid,
                            'startSHA256': sha(match.group(4).encode()),
                            'argsSHA256': sha(match.group(5).encode())}
    require(os.getpid() in records, 'process-inventory-unavailable')
    return records


def descendants(table, roots):
    owned = set(roots) & set(table)
    while True:
        expanded = owned | {pid for pid, row in table.items() if row['parentPID'] in owned}
        if expanded == owned:
            return owned
        owned = expanded


def observe(known):
    table = process_table()
    still_owned = {pid for pid, record in known.items() if pid in table and
                   table[pid]['startSHA256'] == record['startSHA256']}
    owned = descendants(table, still_owned | {os.getpid()})
    for pid in owned:
        known[pid] = table[pid]
    return table, owned


def stop_owned(known):
    table, owned = observe(known)
    groups = {table[pid]['processGroup'] for pid in owned if pid != os.getpid()}
    for group in groups:
        require(group != os.getpgrp() and
                all(pid in owned for pid, row in table.items() if row['processGroup'] == group),
                'process-group-scope-rejected')
    for group in groups:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return len(groups)


def owned_listener_count(known):
    table, owned = observe(known)
    require(owned == {os.getpid()}, 'owned-descendants-still-running')
    result = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(os.getpid()),
                             '-iTCP', '-sTCP:LISTEN', '-Fn'], env=QUERY_ENV,
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=15)
    require(result.returncode in (0, 1), 'owned-listener-query-failed')
    return sum(line.startswith(b'n') for line in result.stdout.splitlines())


def diagnostic_records(raw, manifest):
    """Only pinned source locations and fixed diagnostic classes may leave memory."""
    names = {}
    for name, digest in manifest.items():
        names[str(STAGED / 'source' / name)] = (Path(name).name, digest)
        names[str(CURRENT / 'ios-work/source' / name)] = (Path(name).name, digest)
        names[str(CURRENT / 'mac-work/source' / name)] = (Path(name).name, digest)
        names[str(CURRENT / 'protocol-work' / name)] = (Path(name).name, digest)
    records = []
    for line in raw.decode(errors='replace').splitlines():
        match = re.match(r'^(.+\.(?:swift|m|mm|c|h)):(\d+):(?:(\d+):)?\s*'
                         r'(error|warning):\s*(.{0,400})$', line)
        if not match or match.group(1) not in names:
            continue
        message = match.group(5)
        classification = 'compiler-' + match.group(4)
        for pattern, label in [(r'cannot find|has no member|unresolved identifier', 'missing-symbol'),
                               (r'cannot convert|does not conform|type mismatch', 'type-mismatch'),
                               (r'no such module|could not build module', 'module-import'),
                               (r'actor.isolated|main actor|Sendable|concurrent', 'concurrency-isolation'),
                               (r'missing argument|extra argument|argument label', 'call-signature')]:
            if re.search(pattern, message, re.IGNORECASE):
                classification = label
                break
        basename, digest = names[match.group(1)]
        record = {'file': basename, 'line': int(match.group(2)),
                  'column': int(match.group(3)) if match.group(3) else 0,
                  'sourceFileSHA256': digest,
                  'kind': match.group(4), 'classification': classification}
        if record not in records:
            records.append(record)
        if len(records) == 40:
            break
    return records


def test_inventory(source, manifest):
    """Expected framework presence only; never substitute source for runtime counts."""
    expected = {'xctest': False, 'swiftTesting': False}
    for name, digest in manifest.items():
        if not name.startswith('Tests/') or not name.endswith('.swift'):
            continue
        path = source / name
        require(file_hash(path) == digest, 'test-inventory-source-changed')
        text = path.read_text()
        if re.search(r'^\s*import XCTest\s*$', text, re.MULTILINE) and 'XCTestCase' in text:
            expected['xctest'] = True
        if re.search(r'^\s*import Testing\s*$', text, re.MULTILINE):
            expected['swiftTesting'] = True
    return expected


def test_counts(raw, expected):
    text = re.sub(r'\x1b\[[0-9;]*m', '', raw.decode(errors='replace'))
    states = {'xctest': {}, 'swiftTesting': {}}
    for case, state in re.findall(r"Test Case ['\"]([^'\"\n]{1,200})['\"] "
                                  r'(passed|failed|skipped)\b', text):
        # Preserve the existing XCTest case whitelist exactly.
        if re.fullmatch(r'[A-Za-z0-9_. /\[\]-]+', case):
            states['xctest'][case] = state
    for selector, state in re.findall(r'^\W*Test ([A-Za-z_][A-Za-z0-9_.]*)\(\) '
                                      r'(passed|failed|skipped)\b', text, re.MULTILINE):
        selector = selector.rsplit('.', 1)[-1]
        if re.fullmatch(r'[A-Za-z0-9_. /\[\]-]+', selector):
            states['swiftTesting'][selector] = state
    xctest_summaries = re.findall(
        r"Test Suite ['\"](?:All tests|Selected tests)['\"] (passed|failed) at[^\n]*\n"
        r'\s*Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?'
        r'(\d+) failures? \((\d+) unexpected\) in \d+(?:\.\d+)?'
        r'(?: \(\d+(?:\.\d+)?\))? seconds[. \t]*$', text, re.MULTILINE)
    swift_summaries = re.findall(
        r'^\W*Test run with (\d+) tests?(?: in \d+ suites?)? '
        r'(passed|failed) after \d+(?:\.\d+)? seconds?'
        r'(?: with (\d+) issues?)?\.[ \t]*$', text, re.MULTILINE)
    summaries = {'xctest': [], 'swiftTesting': []}
    for state, total, skipped, issues, unexpected in xctest_summaries:
        if int(unexpected) > int(issues):
            continue
        summaries['xctest'].append({'state': state, 'reportedTests': int(total),
                                    'skippedTests': int(skipped or 0), 'failureIssues': int(issues)})
    for total, state, issues in swift_summaries:
        if state == 'passed' and issues and int(issues) != 0:
            continue
        summaries['swiftTesting'].append({'state': state, 'reportedTests': int(total),
                                          'failureIssues': 0 if state == 'passed' else
                                          (int(issues) if issues else None)})
    frameworks = {}
    failed_cases, skipped_cases = [], []
    for library in ('xctest', 'swiftTesting'):
        cases, runs = states[library], summaries[library]
        passed_observed = sum(state == 'passed' for state in cases.values())
        failed = sum(state == 'failed' for state in cases.values())
        skipped = sum(state == 'skipped' for state in cases.values())
        reported = sum(run['reportedTests'] for run in runs)
        issues = (sum(run['failureIssues'] for run in runs)
                  if all(run['failureIssues'] is not None for run in runs) else None)
        summaries_passed = bool(runs) and all(run['state'] == 'passed' for run in runs)
        consistent = bool(runs) and reported >= failed + skipped
        if library == 'xctest':
            skipped = sum(run['skippedTests'] for run in runs)
            consistent &= reported >= failed + skipped
        consistent &= ((summaries_passed and failed == 0 and issues == 0)
                       or (any(run['state'] == 'failed' for run in runs) and failed > 0 and
                           (issues is None or issues >= failed)))
        consistent &= not expected[library] or reported > 0
        passed = reported - skipped if summaries_passed and issues == 0 else passed_observed
        frameworks[library] = {'expected': bool(expected[library]), 'summaryObserved': bool(runs),
                               'summaryConsistent': bool(consistent), 'reportedTests': reported,
                               'executedTests': reported - skipped, 'passedTests': passed,
                               'failedTests': failed, 'skippedTests': skipped,
                               'failureIssues': issues}
        prefix = 'SwiftTesting.' if library == 'swiftTesting' else ''
        failed_cases.extend(prefix + case for case, state in cases.items() if state == 'failed')
        skipped_cases.extend(prefix + case for case, state in cases.items() if state == 'skipped')
    expected_libraries = [key for key, value in expected.items() if value]
    failure_issues = (sum(value['failureIssues'] for value in frameworks.values())
                      if all(value['failureIssues'] is not None for value in frameworks.values()) else None)
    return {'frameworks': frameworks,
            'reportedTests': sum(value['reportedTests'] for value in frameworks.values()),
            'executedTests': sum(value['executedTests'] for value in frameworks.values()),
            'passedTests': sum(value['passedTests'] for value in frameworks.values()),
            'skippedTests': sum(value['skippedTests'] for value in frameworks.values()),
            'failedTests': sum(value['failedTests'] for value in frameworks.values()),
            'failureIssues': failure_issues, 'failedCases': sorted(failed_cases)[:40],
            'skippedCases': sorted(skipped_cases)[:100],
            'testSummaryObserved': bool(expected_libraries) and all(
                frameworks[key]['summaryObserved'] and frameworks[key]['summaryConsistent']
                for key in expected_libraries)}


def phase_failure_classes(raw):
    """Fixed labels from explicit failure signatures; no raw text survives."""
    text = re.sub(r'\x1b\[[0-9;]*m', '', raw.decode(errors='replace')).replace('\u2019', "'")
    text = re.sub(r'[A-Za-z][A-Za-z0-9+.-]*://[^\s\'\"]+', '<url>', text)
    text = re.sub(r'\b(?:token|password|secret|authorization)\s*[:=][^\n]*',
                  '<credential-field>', text, flags=re.IGNORECASE)
    patterns = [
        ('package-resolution', r'could not resolve package dependencies|failed to resolve (?:package )?'
                               r'dependencies|package resolution failed|Package\.resolved (?:file )?'
                               r'is (?:corrupted|malformed)|a resolved file is required when '
                               r'automatic dependency resolution is disabled|out-of-date resolved file'),
        ('package-manifest', r'invalid manifest|Missing or empty JSON output from manifest compilation|'
                             r'serialized JSON uses unsupported version'),
        ('tools-version', r'Swift tools version[^\n]*(?:installed version|no longer supported)|'
                          r'toolchain is invalid'),
        ('transport-policy', r"transport '[^'\n]+' not allowed"),
        ('shallow-repository', r'source repository is shallow[^\n]*reject to clone|'
                              r'Server does not support shallow (?:clients|requests)'),
        ('git-command', r"Git command '[^\n]*' failed:"),
        ('target-dependency-name', r"\bunknown (?:package|dependency) '[^'\n]+' in "
                                   r'(?:dependencies of )?target\b'),
        ('clone', r'(?:failed|unable|could not|couldn\'t) (?:to )?clone (?:the )?repository'),
        ('fetch', r'(?:failed|unable|could not|couldn\'t) (?:to )?fetch(?: updates)? '
                  r'(?:from|repository|remote)|'
                  r'failed to fetch|fetch failed'),
        ('tls', r'SSL certificate problem|certificate verify failed|TLS handshake (?:failed|error)|'
                r'SSL connect error|\bSSL_ERROR_(?:SYSCALL|SSL)\b|gnutls_handshake\(\) failed|'
                r'server certificate verification failed|SSL peer certificate or SSH remote key '
                r'was not OK|TLS connection was non-properly terminated|\bcurl (?:35|51|60)\b'),
        ('network-timeout', r'(?:operation|connection|connect|network|request|transfer|'
                            r'SSL connection|TLS connection) timed out|curl 28\b|'
                            r'failed to connect[^\n]*timeout|NSURLErrorDomain[^\n]*-1001\b'),
        ('http2', r'\bcurl 92\b|\bHTTP/2\b[^\n]*(?:not closed cleanly|stream error|CANCEL|'
                  r'INTERNAL_ERROR|PROTOCOL_ERROR)|error in the HTTP2 framing layer'),
        ('pinned-revision', r'(?:could not|unable to|couldn\'t) (?:find|check out) (?:the )?revision|'
                           r'revision[^\n]*(?:does not exist|could not be found|is not a valid git object)|'
                           r'unknown revision|invalid object name|bad object [0-9a-f]{7,40}\b|'
                           r'reference [^\n]{1,200} is not a tree|fatal: (?:bad|invalid) revision'),
        ('version-resolve', r'no versions of [^\n]+ match|incompatible version requirements|'
                           r'version [^\n]+ does not match [^\n]+ requirement|'
                           r'dependencies could not be resolved because|'
                           r'versions of [^\n]+ are incompatible'),
        ('sign-permission', r'Permission denied|Operation not permitted|CodeSign[^\n]*failed|'
                            r'code signing is required|no signing certificate|'
                            r'requires a provisioning profile|signing[^\n]*requires[^\n]*team|'
                            r'user interaction is not allowed|errSec(?:AuthFailed|InteractionNotAllowed)'),
    ]
    labels = [label for label, pattern in patterns if re.search(pattern, text, re.IGNORECASE)]
    # SwiftPM's ModulesGraph formatter uses this exact single-line message.
    # Keep the product, package identity and our three target names fixed.
    citadel_targets = ('AetherScreensSSHUIFixture', 'AetherScreensSSH',
                       'AetherScreensSSHTests')
    if any(("dependency 'Citadel' in target '" + target +
            "' requires explicit declaration; reference the package in the target "
            "dependency with '.product(name: \"Citadel\", package: \"citadel\")'")
           in text for target in citadel_targets):
        labels.append('citadel-byname-package-name')
    return labels


def environment():
    home, temporary, cache = CURRENT / 'home', CURRENT / 'tmp', CURRENT / 'cache'
    for path in (home, temporary, cache):
        path.mkdir(mode=0o700)
    return dict(QUERY_ENV, HOME=str(home), CFFIXED_USER_HOME=str(home),
                TMPDIR=str(temporary) + '/', USER='chenxu', LOGNAME='chenxu', TERM='dumb',
                DEVELOPER_DIR=str(DEVELOPER), OS_LOG_DISABLED='YES',
                GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                XDG_CACHE_HOME=str(cache), SWIFTPM_MODULECACHE_OVERRIDE=str(cache / 'modules'),
                CLANG_MODULE_CACHE_PATH=str(cache / 'clang'),
                AETHERSCREENS_HEADLESS_QA='1', AETHERSCREENS_QA_ISOLATED='1')


def dependency_failure_records(raw):
    """Reduce SwiftPM's failure header and indented Git output to fixed labels."""
    text = re.sub(r'\x1b\[[0-9;]*m', '', raw.decode(errors='replace')).replace('\u2019', "'")
    lines, records = text.splitlines(), set()
    url_pattern = r'[A-Za-z][A-Za-z0-9+.-]*://[^\s\'\"<>\x00-\x20]+'
    seed_identities = {(DEPENDENCY_INPUTS / (identity + '.git')).as_uri(): identity
                       for identity in DEPENDENCY_IDENTITIES.values()}
    allowed = {'clone', 'fetch', 'tls', 'network-timeout', 'http2',
               'pinned-revision', 'version-resolve', 'sign-permission',
               'transport-policy', 'shallow-repository', 'git-command'}
    for index, line in enumerate(lines):
        if not re.search(r'\b(?:clone|fetch)\b', line, re.IGNORECASE):
            continue
        operation = set(phase_failure_classes(line.encode())) & {'clone', 'fetch'}
        if not operation:
            continue
        end = index + 1
        while end < len(lines) and end - index <= 64 and lines[end].startswith((' ', '\t')):
            end += 1
        context = lines[index:end]
        urls = re.findall(url_pattern, line)
        if not urls:
            # Fetch headers omit the URL; only explicit Git error lines supply it.
            urls = [url for detail in context[1:]
                    if re.search(r'(?:fatal|error):|unable to access', detail, re.IGNORECASE)
                    for url in re.findall(url_pattern, detail)]
        identities = {seed_identities.get(url, DEPENDENCY_IDENTITIES.get(
            url.rstrip(':/'), 'unknown')) for url in urls}
        identity = next(iter(identities)) if len(identities) == 1 else 'unknown'
        classes = set(phase_failure_classes('\n'.join(context).encode())) & allowed
        records.update((identity, classification) for classification in operation | classes)
    return [{'identity': identity, 'classification': classification}
            for identity, classification in sorted(records)[:40]]


def run_command(argv, env, cwd, phase, receipt, known, manifest, timeout=1800):
    before = budget()
    record = {'phase': phase, 'state': 'running', 'argvSHA256': sha(encoded(argv)),
              'allocatedBytesBefore': before['allocatedBytes'], 'freeBytesBefore': before['freeBytes']}
    receipt['commands'].append(record)
    print(json.dumps({'phase': phase, 'state': 'running'}, sort_keys=True), flush=True)
    child_env = dict(env)
    if phase in ('core-tests', 'mac-build', 'ios-compile', 'package-graph'):
        child_env.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='http.version',
                         GIT_CONFIG_VALUE_0='HTTP/1.1')
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, cwd=cwd, env=child_env, start_new_session=True)
    table = process_table()
    for pid in descendants(table, {process.pid}):
        known[pid] = table[pid]
    record['pid'] = process.pid
    record['processGroup'] = process.pid
    record['startSHA256'] = table.get(process.pid, {}).get('startSHA256')
    output = bytearray()
    selector = selectors.DefaultSelector()
    for stream in (process.stdout, process.stderr):
        os.set_blocking(stream.fileno(), False)
        selector.register(stream, selectors.EVENT_READ)
    started, checked = time.monotonic(), 0.0
    rejection = None
    try:
        while selector.get_map() or process.poll() is None:
            for key, _ in selector.select(0.5):
                block = os.read(key.fileobj.fileno(), 65536)
                if block:
                    if len(output) + len(block) > MAX_OUTPUT:
                        raise Rejected('memory-output-budget-exceeded')
                    output.extend(block)
                else:
                    selector.unregister(key.fileobj)
            now = time.monotonic()
            if now - checked >= 2:
                observe(known)
                budget()
                checked = now
            require(now - started <= timeout, 'phase-timeout')
    except (Rejected, KeyboardInterrupt) as failure:
        rejection = str(failure) if isinstance(failure, Rejected) else 'interrupted'
        receipt['stoppedOwnedProcessGroups'] += stop_owned(known)
    finally:
        selector.close()
        process.wait(timeout=30)
        process.stdout.close()
        process.stderr.close()
    record.update(state='terminal', exitCode=process.returncode,
                  durationSeconds=round(time.monotonic() - started, 3),
                  capturedOutputBytes=len(output), diagnostics=diagnostic_records(output, manifest))
    if phase == 'package-graph':
        record.update(testsExecuted=False, runtimeAcceptance=False, executedTests=0,
                      capturedOutputSHA256=sha(output))
    if phase in ('core-tests', 'protocol-tests'):
        expected = test_inventory(cwd, manifest)
        record.update(test_counts(output, expected))
    if process.returncode != 0:
        record['phaseFailureClasses'] = phase_failure_classes(output)
        record['dependencyFailures'] = dependency_failure_records(output)
        if not (record['diagnostics'] or record['phaseFailureClasses'] or record['dependencyFailures']):
            record['phaseFailureClasses'] = ['unclassified-nonzero-exit']
            record['capturedOutputSHA256'] = sha(output)
    output.clear()
    if rejection:
        record['failureCase'] = rejection
        raise Rejected(rejection)
    after = budget()
    record.update(allocatedBytesAfter=after['allocatedBytes'], freeBytesAfter=after['freeBytes'])
    require(process.returncode == 0, phase + '-failed')
    return record


def review_pin(source_manifest_sha):
    return sha(encoded({'sourceManifestSHA256': source_manifest_sha,
                        'compilationCondition': 'AETHERSCREENS_QA_ISOLATION',
                        'ordinaryAssertionsSuppressed': False,
                        'coverage': 'ordinary-core-ssh-widget-package-tests'}))


def package_graph_review_pin(source_manifest_sha, seed_manifest_sha):
    return sha(encoded({'sourceManifestSHA256': source_manifest_sha,
                        'dependencySeedManifestSHA256': seed_manifest_sha,
                        'coverage': 'package-graph-only', 'dependencyTransport': 'file',
                        'testsExecuted': False, 'runtimeAcceptance': False}))


def phases(mode, source, env, receipt, known, manifest, args):
    if mode in ('mac-build', 'ios-compile') and getattr(
            args, 'dependency_seed_manifest_sha256', None):
        mirrors = {'version': 1, 'object': [
            {'original': pin['location'], 'mirror':
             (DEPENDENCY_INPUTS / (identity + '.git')).as_uri()}
            for identity, pin in sorted(dependency_pins(source).items())]}
        mirror_path = CURRENT / 'mirrors.json'
        write_exclusive(mirror_path, mirrors)
        env = dict(env, SWIFTPM_MIRROR_CONFIG=str(mirror_path), GIT_ALLOW_PROTOCOL='file')
        receipt['dependencyMirrorConfigSHA256'] = file_hash(mirror_path)
    if mode == 'mac-build':
        work = CURRENT / 'mac-work'
        work.mkdir(mode=0o700)
        copied = work / 'source'
        shutil.copytree(source, copied)
        verify_tree(copied, manifest)
        helper = runpy.run_path(str(copied / 'scripts/build_macos_app.py'))
        helper_failures = []
        def supervised(argv, helper_env, cwd, phase, records):
            build_env = dict(helper_env, LC_ALL='C',
                             XDG_CACHE_HOME=env['XDG_CACHE_HOME'],
                             SWIFTPM_MODULECACHE_OVERRIDE=env['SWIFTPM_MODULECACHE_OVERRIDE'],
                             CLANG_MODULE_CACHE_PATH=env['CLANG_MODULE_CACHE_PATH'])
            try:
                if phase == 'build':
                    require(argv[0] == str(XCODEBUILD) and argv[1] == 'build',
                            'mac-native-build-command-required')
                    project = CURRENT / 'mac-build/project/AetherScreensMacRelease.xcodeproj'
                    pins = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
                    require(file_hash(pins) == manifest['Package.resolved'] and
                            file_hash(copied / 'Package.resolved') == manifest['Package.resolved'],
                            'mac-generated-lock-mismatch')
                    if getattr(args, 'dependency_seed_manifest_sha256', None):
                        require('-scmProvider' not in argv, 'mac-scm-provider-already-set')
                        build_env.update(SWIFTPM_MIRROR_CONFIG=env['SWIFTPM_MIRROR_CONFIG'],
                                         GIT_ALLOW_PROTOCOL=env['GIT_ALLOW_PROTOCOL'])
                        argv = list(argv) + ['-scmProvider', 'system']
                try:
                    record = run_command(argv, build_env, cwd, 'mac-' + phase,
                                         receipt, known, manifest)
                finally:
                    if phase == 'build':
                        require(file_hash(pins) == manifest['Package.resolved'],
                                'mac-generated-lock-changed')
            except Rejected as failure:
                helper_failures.append(str(failure))
                raise helper['Rejected'](str(failure))
            records.append({key: record[key] for key in ('phase', 'state', 'exitCode', 'argvSHA256')})
        helper['main'].__globals__['command'] = supervised
        previous = sys.argv
        try:
            sys.argv = [str(copied / 'scripts/build_macos_app.py'),
                        '--build-root', str(CURRENT / 'mac-build'), '--xcodegen', str(GENERATOR),
                        '--build-number', '29']
            require(helper['main']() == 0, helper_failures[-1] if helper_failures else 'mac-helper-failed')
        finally:
            sys.argv = previous
            for name, digest in manifest.items():
                require(file_hash(copied / name) == digest, 'mac-copied-input-changed')
        receipt['unsignedMacHostAndWidgetCompiled'] = True
    elif mode == 'package-graph':
        seed_sha = getattr(args, 'dependency_seed_manifest_sha256', None)
        require(hash_value(seed_sha), 'package-graph-seed-pin-required')
        require(args.authorize_package_graph and args.package_graph_isolation_sha256 ==
                package_graph_review_pin(args.manifest_sha256, seed_sha),
                'package-graph-isolation-review-required')
        mirrors = {'version': 1, 'object': [
            {'original': pin['location'], 'mirror':
             (DEPENDENCY_INPUTS / (identity + '.git')).as_uri()}
            for identity, pin in sorted(dependency_pins(source).items())]}
        mirror_path = CURRENT / 'mirrors.json'
        write_exclusive(mirror_path, mirrors)
        env = dict(env, SWIFTPM_MIRROR_CONFIG=str(mirror_path), GIT_ALLOW_PROTOCOL='file')
        receipt['dependencyMirrorConfigSHA256'] = file_hash(mirror_path)
        argv = [str(SWIFT), 'package', '--package-path', str(source),
                '--force-resolved-versions', '--disable-keychain', '--disable-netrc',
                '--scratch-path', str(CURRENT / 'package-graph-build'),
                '--cache-path', str(CURRENT / 'cache/swiftpm'),
                '--config-path', str(CURRENT / 'cache/swiftpm-config'),
                '--security-path', str(CURRENT / 'cache/swiftpm-security'),
                'show-dependencies', '--format', 'json']
        run_command(argv, env, source, 'package-graph', receipt, known, manifest, timeout=300)
        receipt.update(packageGraphLoaded=True, testsExecuted=False, runtimeAcceptance=False,
                       fullCoreTestsAccepted=False, transportOrUIAccepted=False)
    elif mode == 'core-tests':
        require(args.authorize_core_tests and args.core_isolation_sha256 ==
                review_pin(args.manifest_sha256), 'core-isolation-review-required')
        if getattr(args, 'dependency_seed_manifest_sha256', None):
            mirrors = {'version': 1, 'object': [
                {'original': pin['location'], 'mirror':
                 (DEPENDENCY_INPUTS / (identity + '.git')).as_uri()}
                for identity, pin in sorted(dependency_pins(source).items())]}
            mirror_path = CURRENT / 'mirrors.json'
            write_exclusive(mirror_path, mirrors)
            env = dict(env, SWIFTPM_MIRROR_CONFIG=str(mirror_path), GIT_ALLOW_PROTOCOL='file')
            receipt['dependencyMirrorConfigSHA256'] = file_hash(mirror_path)
        argv = [str(SWIFT), 'test', '--package-path', str(source),
                '--force-resolved-versions', '--disable-keychain', '--disable-netrc',
                '--scratch-path', str(CURRENT / 'core-build'),
                '--cache-path', str(CURRENT / 'cache/swiftpm'),
                '--config-path', str(CURRENT / 'cache/swiftpm-config'),
                '--security-path', str(CURRENT / 'cache/swiftpm-security'),
                '-Xswiftc', '-DAETHERSCREENS_QA_ISOLATION']
        record = run_command(argv, env, source, 'core-tests', receipt, known, manifest)
        require(record['testSummaryObserved'] and record['executedTests'] > 0 and
                record['failedTests'] == 0 and record['failureIssues'] == 0,
                'core-test-summary-required')
        receipt['testsExecuted'] = True
    elif mode == 'protocol-tests':
        # Compile exact production protocol files with their original XCTest
        # assertions. This bounded subset has no third-party dependencies and
        # is reported separately from the full package and transport/UI gates.
        require(args.authorize_core_tests and args.core_isolation_sha256 ==
                review_pin(args.manifest_sha256), 'core-isolation-review-required')
        work = CURRENT / 'protocol-work'
        work.mkdir(mode=0o700)
        selected = [
            'Sources/AetherScreensCore/RFB/RFBAppleCurtain.swift',
            'Sources/AetherScreensCore/RFB/RFBAppleDisplayLayout.swift',
            'Sources/AetherScreensCore/RFB/RFBConstants.swift',
            'Sources/AetherScreensCore/RFB/RFBEncoder.swift',
            'Sources/AetherScreensCore/RFB/RFBPacket.swift',
            'Tests/AetherScreensCoreTests/AppleCurtainTests.swift',
            'Tests/AetherScreensCoreTests/AppleDisplayLayoutTests.swift',
        ]
        subset = {}
        for name in selected:
            require(name in manifest and file_hash(source / name) == manifest[name],
                    'protocol-subset-source-mismatch')
            target = work / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream:
                stream.write((source / name).read_bytes())
            subset[name] = manifest[name]
        specification = (
            '// swift-tools-version: 5.9\nimport PackageDescription\n'
            'let package = Package(name: "AetherScreensProtocolQA", '
            'platforms: [.macOS(.v14)], targets: ['
            '.target(name: "AetherScreensCore", path: "Sources/AetherScreensCore"), '
            '.testTarget(name: "AetherScreensCoreTests", dependencies: ["AetherScreensCore"], '
            'path: "Tests/AetherScreensCoreTests")])\n').encode()
        with (work / 'Package.swift').open('xb') as stream:
            stream.write(specification)
        subset['Package.swift'] = sha(specification)
        verify_tree(work, subset)
        record = run_command([
            str(SWIFT), 'test', '--package-path', str(work),
            '--disable-keychain', '--disable-netrc',
            '--scratch-path', str(CURRENT / 'protocol-build'),
            '--cache-path', str(CURRENT / 'cache/swiftpm'),
            '--config-path', str(CURRENT / 'cache/swiftpm-config'),
            '--security-path', str(CURRENT / 'cache/swiftpm-security'),
            '-Xswiftc', '-DAETHERSCREENS_QA_ISOLATION'],
            env, work, 'protocol-tests', receipt, known, subset)
        require(record['testSummaryObserved'] and record['executedTests'] > 0 and
                record['failedTests'] == 0 and record['failureIssues'] == 0,
                'protocol-test-summary-required')
        for name in selected:
            require(file_hash(work / name) == manifest[name], 'protocol-subset-source-changed')
        receipt.update(testsExecuted=True, protocolSubsetTestsExecuted=True,
                       fullCoreTestsAccepted=False, transportOrUIAccepted=False)
    else:
        work = CURRENT / 'ios-work'
        work.mkdir(mode=0o700)
        copied = work / 'source'
        shutil.copytree(source, copied)
        verify_tree(copied, manifest)
        project_dir = copied / 'ios'
        specification = (project_dir / 'project.yml').read_bytes()
        require(file_hash(project_dir / 'project.yml') == manifest['ios/project.yml'] and
                sha(specification) == '0be65e02f1f15861da77d56a121b8195e30ea50f6852a2a955231a6649a7a1d8',
                'ios-production-specification-changed')
        path_changes = (
            (b'    path: ..\n', b'    path: ../source\n', 1),
            (b'      - AetherScreensIOSApp.swift\n', b'      - ../source/ios/AetherScreensIOSApp.swift\n', 1),
            (b'      - path: ../Sources/AetherScreensAppIntents/SavedComputerIntents.swift\n', b'      - path: ../source/Sources/AetherScreensAppIntents/SavedComputerIntents.swift\n', 1),
            (b'      - Assets.xcassets\n', b'      - ../source/ios/Assets.xcassets\n', 1),
            (b'      - path: ../assets/localization\n', b'      - path: ../source/assets/localization\n', 1),
            (b'      path: Info.plist\n', b'      path: AetherScreensIOS-Info.plist\n', 1),
            (b'        CODE_SIGN_ENTITLEMENTS: ../assets/AetherScreensWidgets.entitlements\n', b'        CODE_SIGN_ENTITLEMENTS: ../source/assets/AetherScreensWidgets.entitlements\n', 2),
            (b'      - path: ../Sources/AetherScreensWidgets\n', b'      - path: ../source/Sources/AetherScreensWidgets\n', 1),
            (b'      - path: ../assets/widget-localization\n', b'      - path: ../source/assets/widget-localization\n', 1),
            (b'      path: build/AetherScreensWidgets-Info.plist\n', b'      path: AetherScreensWidgets-Info.plist\n', 1),
            (b'      - UITests\n', b'      - ../source/ios/UITests\n', 1),
        )
        qa_specification = specification
        for old, new, count in path_changes:
            require(qa_specification.count(old) == count, 'ios-owned-path-not-unique')
            qa_specification = qa_specification.replace(old, new, count)
        generated = work / 'generated'
        generated.mkdir(mode=0o700)
        generated_info = generated / 'AetherScreensIOS-Info.plist'
        original_info = (project_dir / 'Info.plist').read_bytes()
        require(file_hash(project_dir / 'Info.plist') == manifest['ios/Info.plist'] and
                sha(original_info) == manifest['ios/Info.plist'], 'ios-original-info-changed')
        with generated_info.open('xb') as stream:
            stream.write(original_info)
        require(file_hash(generated_info) == manifest['ios/Info.plist'],
                'ios-generated-info-copy-mismatch')
        qa_spec = generated / '.aetherscreens-qa-project.yml'
        with qa_spec.open('xb') as stream:
            stream.write(qa_specification)
        require(file_hash(qa_spec) == sha(qa_specification), 'ios-owned-specification-mismatch')
        receipt['iosProjectSpecSHA256'] = sha(qa_specification)
        try:
            run_command([str(GENERATOR), 'generate', '--spec', str(qa_spec)],
                        env, generated, 'ios-generate', receipt, known, manifest)
        finally:
            for name, digest in manifest.items():
                require(file_hash(copied / name) == digest, 'ios-generated-input-changed')
        project = generated / 'AetherScreensIOS.xcodeproj'
        pins = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        pins.parent.mkdir(parents=True, exist_ok=True)
        require(not os.path.lexists(pins), 'generated-pins-exist')
        with pins.open('xb') as stream:
            stream.write((source / 'Package.resolved').read_bytes())
        # HOME and CFFIXED_USER_HOME already point at this round's fresh home.
        netrc = Path(env['HOME']) / '.netrc'
        with netrc.open('xb'):
            pass
        netrc.chmod(0o600)
        require(file_hash(pins) == manifest['Package.resolved'] and
                file_hash(copied / 'Package.resolved') == manifest['Package.resolved'],
                'ios-generated-lock-mismatch')
        argv = [str(XCODEBUILD), 'build', '-project', str(project),
                     '-scheme', 'AetherScreensIOS', '-configuration', 'Release',
                     '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
                     '-derivedDataPath', str(work / 'DerivedData'),
                     '-clonedSourcePackagesDirPath', str(work / 'SourcePackages'),
                     '-packageAuthorizationProvider', 'netrc',
                     '-onlyUsePackageVersionsFromResolvedFile', 'CODE_SIGNING_ALLOWED=NO',
                     'CODE_SIGNING_REQUIRED=NO', 'CURRENT_PROJECT_VERSION=29',
                     'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES',
                     'CLANG_MODULE_CACHE_PATH=' + env['CLANG_MODULE_CACHE_PATH']]
        if getattr(args, 'dependency_seed_manifest_sha256', None):
            argv.extend(['-scmProvider', 'system'])
        try:
            run_command(argv, env, generated, 'ios-compile', receipt, known, manifest)
        finally:
            for name, digest in manifest.items():
                require(file_hash(copied / name) == digest, 'ios-compiled-input-changed')
            require(file_hash(pins) == manifest['Package.resolved'] and
                    file_hash(copied / 'Package.resolved') == manifest['Package.resolved'],
                    'ios-generated-lock-changed')
        receipt['unsignedIOSSimulatorCompiled'] = True


def write_exclusive(path, value):
    with path.open('xb') as stream:
        stream.write(encoded(value))
    path.chmod(0o600)


def run(args):
    seed_manifest_sha = getattr(args, 'dependency_seed_manifest_sha256', None)
    receipt = {'schema': 1, 'mode': args.mode, 'state': 'preflight', 'exitCode': 2,
               'commands': [], 'stoppedOwnedProcessGroups': 0, 'testsExecuted': False,
               'appsInstalledOrLaunched': False, 'signingPerformed': False,
               'runtimeAcceptance': False, 'rawOutputPersisted': False,
               'GUIAccessed': False, 'realCredentialsAccessed': False,
               'realClipboardAccessed': False, 'sourceArchiveSHA256': args.source_sha256,
               'sourceManifestSHA256': args.manifest_sha256,
               'buildNumber': '29', 'acceptedPrivateBuild29': False,
               'allocatedBytesLimit': MAX_BYTES, 'minimumFreeBytes': MIN_FREE}
    created, known, manifest, source = False, {}, None, STAGED / 'source'
    try:
        host_preflight()
        safe_path(ROOT)
        require(ROOT.is_dir() and ROOT.stat().st_uid == os.getuid(), 'owner-root-required')
        owner = pinned_json(OWNER, args.owner_sha256)
        require(owner == {'schema': 1, 'purpose': 'aetherscreens-first-release-headless-qa',
                          'ownerUID': os.getuid(), 'root': str(ROOT),
                          'toolchainManifestSHA256': TOOLCHAIN_MANIFEST_SHA}, 'owner-marker-rejected')
        root_owner_path = ROOT / '.aetherscreens-owner.json'
        root_owner_sha = file_hash(root_owner_path)
        root_owner = pinned_json(root_owner_path, root_owner_sha)
        require(isinstance(root_owner, dict) and root_owner.get('schema') == 1 and
                root_owner.get('purpose') == 'aetherscreens-first-release-qa' and
                root_owner.get('ownerUID') == os.getuid() and root_owner.get('root') == str(ROOT) and
                root_owner.get('repositoryName') == 'AetherScreens' and
                re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',
                             root_owner.get('operationID', '')) is not None, 'root-marker-rejected')
        receipt['rootOwnerSHA256Before'] = root_owner_sha
        require(Path(__file__).resolve() == ROOT / 'macmini_headless_worker.py' and
                file_hash(Path(__file__)) == args.worker_sha256, 'worker-code-pin-required')
        receipt['workerSHA256Before'] = args.worker_sha256
        with exclusive():
            require(not os.path.lexists(CURRENT), 'previous-current-must-be-closed-and-cleaned')
            require(not seed_manifest_sha or args.mode in
                    ('core-tests', 'package-graph', 'mac-build', 'ios-compile'),
                    'dependency-seed-mode-rejected')
            manifest = pinned_json(STAGED / 'source-manifest.json', args.manifest_sha256)
            validate_manifest(manifest)
            require(file_hash(STAGED / 'source.tgz') == args.source_sha256, 'archive-hash-mismatch')
            tools = pinned_json(TOOLCHAIN / 'toolchain-manifest.json', TOOLCHAIN_MANIFEST_SHA)
            validate_manifest(tools, toolchain=True)
            receipt['toolchainTreeSHA256Before'] = verify_tree(
                TOOLCHAIN, tools, ignored=('toolchain-manifest.json',))
            require(os.access(GENERATOR, os.X_OK), 'generator-not-executable')
            if args.mode in ('core-tests', 'protocol-tests'):
                require(args.authorize_core_tests and args.core_isolation_sha256 ==
                        review_pin(args.manifest_sha256), 'core-isolation-review-required')
            if args.mode == 'package-graph':
                require(hash_value(seed_manifest_sha), 'package-graph-seed-pin-required')
                require(args.authorize_package_graph and args.package_graph_isolation_sha256 ==
                        package_graph_review_pin(args.manifest_sha256, seed_manifest_sha),
                        'package-graph-isolation-review-required')
            receipt['budgetBefore'] = budget()
            CURRENT.mkdir(mode=0o700)
            created = True
            marker = {'schema': 1, 'purpose': 'aetherscreens-qa-artifacts',
                      'ownerUID': os.getuid(), 'root': str(CURRENT), 'repository': str(source),
                      'closed': False, 'evidence': [], 'producerSHA256': args.worker_sha256}
            write_exclusive(CURRENT / ROUND_OWNER, marker)
            receipt['initialMarkerSHA256'] = file_hash(CURRENT / ROUND_OWNER)
            receipt['sourceReused'] = os.path.lexists(source)
            if receipt['sourceReused']:
                require(source.is_dir(), 'immutable-source-directory-required')
                receipt['sourceTreeSHA256Before'] = verify_tree(source, manifest)
            else:
                receipt['sourceTreeSHA256Before'] = extract_source(STAGED / 'source.tgz', source, manifest)
            receipt['sourceFileCount'] = len(manifest)
            if seed_manifest_sha:
                receipt['dependencyInputsBefore'] = verify_dependency_seeds(
                    source, seed_manifest_sha)
            env = environment()
            known[os.getpid()] = process_table()[os.getpid()]
            phases(args.mode, source, env, receipt, known, manifest, args)
            receipt['sourceTreeSHA256After'] = verify_tree(source, manifest)
            receipt['toolchainTreeSHA256After'] = verify_tree(
                TOOLCHAIN, tools, ignored=('toolchain-manifest.json',))
            receipt['workerSHA256After'] = file_hash(Path(__file__))
            require(receipt['workerSHA256After'] == args.worker_sha256, 'worker-code-changed')
            receipt['ownedNetworkListeners'] = owned_listener_count(known)
            require(receipt['ownedNetworkListeners'] == 0, 'owned-listener-remains')
            receipt['budgetAfter'] = budget()
            receipt.update(state='headless-phase-complete', exitCode=0)
    except Rejected as failure:
        receipt['state'] = str(failure)
    except KeyboardInterrupt:
        receipt['state'] = 'interrupted'
    except Exception:
        receipt['state'] = 'worker-error'
    finally:
        if created:
            try:
                table, owned = observe(known)
                if owned != {os.getpid()}:
                    receipt['stoppedOwnedProcessGroups'] += stop_owned(known)
                    # Reap only our direct children; never terminate a foreign process.
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        try:
                            os.waitpid(-1, os.WNOHANG)
                        except ChildProcessError:
                            pass
                        table, owned = observe(known)
                        if owned == {os.getpid()}:
                            break
                        time.sleep(0.2)
                receipt['ownedNetworkListeners'] = owned_listener_count(known)
                receipt['ownedProcessInventory'] = sorted(known.values(), key=lambda item: item['pid'])
                if manifest is not None and source.is_dir():
                    receipt['sourceTreeSHA256After'] = verify_tree(source, manifest)
                if seed_manifest_sha and 'dependencyInputsBefore' in receipt:
                    receipt['dependencyInputsAfter'] = verify_dependency_seeds(
                        source, seed_manifest_sha)
                    require(receipt['dependencyInputsAfter'] == receipt['dependencyInputsBefore'],
                            'dependency-inputs-changed')
                receipt['workerSHA256After'] = file_hash(Path(__file__))
                require(receipt['workerSHA256After'] == args.worker_sha256, 'worker-code-changed')
                receipt['rootOwnerSHA256After'] = file_hash(root_owner_path)
                require(receipt['rootOwnerSHA256After'] == root_owner_sha, 'root-marker-changed')
                require(file_hash(OWNER) == args.owner_sha256, 'headless-marker-changed')
                receipt['sourceArchiveSHA256After'] = file_hash(STAGED / 'source.tgz')
                require(receipt['sourceArchiveSHA256After'] == args.source_sha256 and
                        file_hash(STAGED / 'source-manifest.json') == args.manifest_sha256,
                        'staged-source-changed')
                if 'toolchainTreeSHA256Before' in receipt:
                    receipt['toolchainTreeSHA256After'] = verify_tree(
                        TOOLCHAIN, tools, ignored=('toolchain-manifest.json',))
                terminal_budget = tree_fingerprint(ROOT)
                terminal_budget['freeBytes'] = shutil.disk_usage(ROOT).free
                receipt['budgetAfter'] = terminal_budget
                receipt['treeBeforeReceipt'] = tree_fingerprint(CURRENT)
                require(receipt['ownedNetworkListeners'] == 0, 'owned-listener-remains')
                marker['closed'] = True
            except Exception:
                receipt.update(state='terminal-closure-unverified', exitCode=2)
                marker['closed'] = False
            receipt_path = CURRENT / 'worker-receipt.json'
            write_exclusive(receipt_path, receipt)
            marker['evidence'] = [{'path': str(receipt_path), 'sha256': file_hash(receipt_path)}]
            marker_path = CURRENT / ROUND_OWNER
            with marker_path.open('wb') as stream:
                stream.write(encoded(marker))
            terminal = {'state': receipt['state'], 'exitCode': receipt['exitCode'],
                        'mode': args.mode, 'closed': marker['closed'],
                        'receiptSHA256': file_hash(receipt_path),
                        'markerSHA256': file_hash(marker_path),
                        'ownedNetworkListeners': receipt.get('ownedNetworkListeners'),
                        'commands': receipt['commands']}
            terminal.update(tree_fingerprint(CURRENT))
        else:
            terminal = {'state': receipt['state'], 'exitCode': receipt['exitCode'],
                        'mode': args.mode, 'currentCreated': False}
        print(json.dumps(terminal, sort_keys=True), flush=True)
    return receipt['exitCode']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', required=True,
                        choices=['mac-build', 'core-tests', 'protocol-tests', 'ios-compile',
                                 'package-graph'])
    for name in ('source-sha256', 'manifest-sha256', 'owner-sha256', 'worker-sha256'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--authorize-core-tests', action='store_true')
    parser.add_argument('--core-isolation-sha256')
    parser.add_argument('--authorize-package-graph', action='store_true')
    parser.add_argument('--package-graph-isolation-sha256')
    parser.add_argument('--dependency-seed-manifest-sha256')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        require(all(hash_value(getattr(args, name)) for name in
                    ('source_sha256', 'manifest_sha256', 'owner_sha256', 'worker_sha256')),
                'invalid-cli-pin')
        require(args.dependency_seed_manifest_sha256 is None or
                (args.mode in ('core-tests', 'package-graph', 'mac-build', 'ios-compile') and
                 hash_value(args.dependency_seed_manifest_sha256)),
                'dependency-seed-cli-pin')
        return run(args)
    except Rejected as failure:
        print(json.dumps({'state': str(failure), 'exitCode': 2}, sort_keys=True), flush=True)
    except Exception:
        print(json.dumps({'state': 'worker-terminal-error', 'exitCode': 2}, sort_keys=True), flush=True)
    return 2


if __name__ == '__main__':
    sys.exit(main())
