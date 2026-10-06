#!/usr/bin/env python3
"""Prepare one fixed set of ten genuine, pinned public Git inputs on Mac mini.

This explicitly invoked tool never builds/tests, changes source/tools/accounts,
retries, replaces an existing input root, or deletes a partial result. Successful
inputs are reusable only through their pinned manifest and content verification.
Failures retain a closed ownership receipt for separately reviewed cleanup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import selectors
import shutil
import stat
import subprocess
import sys
import time
from types import SimpleNamespace


ROOT = Path('/Users/chenxu/aetherscreens-first-release-qa')
GIT = '/usr/bin/git'


def pinned_tool(path, expected):
    if re.fullmatch('[0-9a-f]{64}', expected) is None:
        raise ValueError('tool-pin')
    for part in [path] + list(path.parents):
        if part.is_symlink():
            raise ValueError('tool-link')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or
                before.st_nlink != 1 or before.st_size > 1024 ** 2):
            raise ValueError('tool-file')
        with os.fdopen(os.dup(descriptor), 'rb') as stream:
            raw = stream.read(1024 ** 2 + 1)
        after = os.fstat(descriptor)
        stable = lambda value: (value.st_dev, value.st_ino, value.st_mode, value.st_uid,
                                value.st_nlink, value.st_size, value.st_mtime_ns, value.st_ctime_ns)
        if stable(before) != stable(after) or hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError('tool-hash')
    finally:
        os.close(descriptor)


def run_git(api, argv, kind, identity, env, receipt, known, timeout=30):
    """Bound output in memory and supervise only this tool's own process group."""
    record = {'operation': kind, 'identity': identity, 'state': 'running'}
    receipt['commands'].append(record)
    process = subprocess.Popen([GIT] + argv, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               cwd=api.DEPENDENCY_INPUTS / 'preparation-home',
                               env=env, start_new_session=True)
    selector = selectors.DefaultSelector()
    os.set_blocking(process.stdout.fileno(), False)
    selector.register(process.stdout, selectors.EVENT_READ)
    raw = bytearray()
    started, checked, rejected = time.monotonic(), 0.0, None
    try:
        api.observe(known)
        while selector.get_map() or process.poll() is None:
            for key, _ in selector.select(0.5):
                block = os.read(key.fileobj.fileno(), 65536)
                if not block:
                    selector.unregister(key.fileobj)
                else:
                    api.require(len(raw) + len(block) <= api.MAX_OUTPUT, 'seed-memory-output-budget')
                    raw.extend(block)
            now = time.monotonic()
            if now - checked >= 2:
                api.observe(known)
                api.budget()
                api.require(api.allocated_bytes(api.DEPENDENCY_INPUTS) <= api.MAX_SEED_BYTES,
                            'seed-total-byte-budget')
                count = sum(len(names) for _, _, names in
                            os.walk(api.DEPENDENCY_INPUTS, followlinks=False))
                api.require(count <= api.MAX_SEED_FILES, 'seed-total-file-budget')
                checked = now
            api.require(now - started <= timeout, 'seed-git-timeout')
    except (api.Rejected, KeyboardInterrupt) as failure:
        rejected = str(failure) if isinstance(failure, api.Rejected) else 'interrupted'
        receipt['stoppedOwnedProcessGroups'] += api.stop_owned(known)
    finally:
        selector.close()
        process.wait(timeout=30)
        process.stdout.close()
    record.update(state='terminal', exitCode=process.returncode,
                  durationSeconds=round(time.monotonic() - started, 3))
    if rejected or process.returncode != 0:
        record['failureClasses'] = api.phase_failure_classes(raw)
        raw.clear()
        raise api.Rejected(rejected or 'seed-git-' + kind + '-failed')
    return bytes(raw)


def prepare_repository(api, pin, env, receipt, known):
    identity, version, revision = pin['identity'], pin['state']['version'], pin['state']['revision']
    slot = api.DEPENDENCY_INPUTS / (identity + '.git')
    tags = (version, 'v' + version)
    patterns = [value for tag in tags for value in ('refs/tags/' + tag, 'refs/tags/' + tag + '^{}')]
    raw = run_git(api, ['ls-remote', '--tags', pin['location']] + patterns,
                  'locate-tag', identity, env, receipt, known)
    refs = {}
    for line in raw.decode('ascii').splitlines():
        match = re.fullmatch(r'([0-9a-f]{40})\t(refs/tags/[^\s]+)', line)
        api.require(match is not None and match.group(2) in patterns and
                    match.group(2) not in refs, 'seed-public-tag-output')
        refs[match.group(2)] = match.group(1)
    eligible = [tag for tag in tags if 'refs/tags/' + tag in refs and
                refs.get('refs/tags/' + tag + '^{}', refs['refs/tags/' + tag]) == revision]
    api.require(eligible, 'seed-public-tag-pin-mismatch')
    tag = eligible[0]
    raw = run_git(api, ['clone', '--bare', '--depth=1', '--single-branch', '--branch', tag,
                       '--template=' + str(api.DEPENDENCY_INPUTS / 'empty-template'),
                       pin['location'], str(slot)], 'clone', identity, env, receipt, known, timeout=180)
    del raw
    api.seed_inventory(slot)
    prefix = ['--git-dir=' + str(slot)]
    def value(arguments, kind):
        return run_git(api, prefix + arguments, kind, identity, env, receipt, known).decode('ascii').strip()
    api.require(value(['rev-parse', '--is-bare-repository'], 'bare') == 'true', 'seed-not-bare')
    api.require(value(['rev-parse', 'HEAD^{commit}'], 'head') == revision, 'seed-head-pin-mismatch')
    api.require(value(['rev-parse', 'refs/tags/' + tag + '^{commit}'], 'tag') == revision,
                'seed-tag-pin-mismatch')
    tag_object = value(['rev-parse', 'refs/tags/' + tag], 'tag-object')
    api.require(tag_object == refs['refs/tags/' + tag], 'seed-tag-object-mismatch')
    api.require(value(['cat-file', '-t', revision], 'commit') == 'commit', 'seed-commit-required')
    tree = value(['rev-parse', revision + '^{tree}'], 'tree')
    api.require(re.fullmatch('[0-9a-f]{40}', tree) is not None and
                value(['cat-file', '-t', tree], 'tree-type') == 'tree', 'seed-tree-required')
    api.require(value(['rev-parse', '--is-shallow-repository'], 'shallow') == 'true' and
                (slot / 'shallow').read_bytes().strip() == revision.encode(), 'seed-shallow-boundary')
    raw = run_git(api, prefix + ['config', '--null', '--local', '--list'], 'config',
                  identity, env, receipt, known)
    config = {}
    for entry in raw.decode('ascii').split('\0'):
        if not entry:
            continue
        key, separator, val = entry.partition('\n')
        api.require(separator and key not in config, 'seed-config-schema')
        config[key] = val
    required_config = {'core.repositoryformatversion': '0', 'core.filemode': 'true',
                       'core.bare': 'true', 'remote.origin.url': pin['location']}
    optional_config = {'core.ignorecase', 'core.precomposeunicode'}
    api.require(all(config.get(key) == val for key, val in required_config.items()) and
                set(config) <= set(required_config) | optional_config and
                all(config[key] in ('true', 'false') for key in optional_config if key in config),
                'seed-config-rejected')
    api.require(not run_git(api, prefix + ['fsck', '--full', '--strict', '--no-reflogs',
                                           '--no-dangling'], 'fsck', identity, env, receipt, known),
                'seed-fsck-output')
    indexes = sorted((slot / 'objects/pack').glob('pack-*.idx'))
    api.require(1 <= len(indexes) <= 64, 'seed-pack-count')
    for index in indexes:
        api.require(re.fullmatch(r'pack-[0-9a-f]{40}\.idx', index.name) is not None and
                    index.with_suffix('.pack').is_file(), 'seed-pack-pair')
        api.require(not run_git(api, prefix + ['verify-pack', str(index)], 'verify-pack',
                                identity, env, receipt, known, timeout=60), 'seed-pack-output')
    inventory = api.seed_inventory(slot)
    return {'originalURL': pin['location'], 'identity': identity, 'version': version,
            'revision': revision, 'tag': tag, 'tagObject': tag_object, 'tree': tree,
            'inventory': inventory}


def prepare_locked(api, args, source_manifest, tools, root_owner_sha):
    source, inputs = api.STAGED / 'source', api.DEPENDENCY_INPUTS
    receipt = {'schema': 1, 'state': 'preparing-dependency-inputs', 'exitCode': 2,
               'commands': [], 'stoppedOwnedProcessGroups': 0, 'testsExecuted': False,
               'GUIAccessed': False, 'realCredentialsAccessed': False,
               'rawOutputPersisted': False, 'allTenGitInputsVerified': False,
               'packageResolvedSHA256': api.DEPENDENCY_LOCK_SHA,
               'workerSHA256': args.worker_sha256, 'preparerSHA256': args.preparer_sha256,
               'sourceArchiveSHA256': args.source_sha256,
               'sourceManifestSHA256': args.manifest_sha256,
               'sourceTreeSHA256Before': api.sha(api.encoded(source_manifest)),
               'toolchainTreeSHA256Before': api.sha(api.encoded(tools)),
               'rootOwnerSHA256Before': root_owner_sha,
               'maximumBytes': api.MAX_SEED_BYTES, 'maximumFiles': api.MAX_SEED_FILES,
               'allocatedBytesLimit': api.MAX_BYTES, 'minimumFreeBytes': api.MIN_FREE}
    inputs.mkdir(mode=0o700)
    marker = {'schema': 1, 'purpose': 'aetherscreens-qa-artifacts', 'ownerUID': os.getuid(),
              'root': str(inputs), 'repository': str(source), 'closed': False, 'evidence': []}
    api.write_exclusive(inputs / api.ROUND_OWNER, marker)
    known = {}
    try:
        known[os.getpid()] = api.process_table()[os.getpid()]
        for name in api.SEED_METADATA_DIRECTORIES:
            (inputs / name).mkdir(mode=0o700)
        env = dict(api.QUERY_ENV, HOME=str(inputs / 'preparation-home'),
                   CFFIXED_USER_HOME=str(inputs / 'preparation-home'),
                   TMPDIR=str(inputs / 'preparation-tmp') + '/',
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                   GIT_CEILING_DIRECTORIES=str(inputs),
                   GIT_TERMINAL_PROMPT='0', GIT_ASKPASS='/usr/bin/false',
                   SSH_ASKPASS='/usr/bin/false', GIT_ALLOW_PROTOCOL='https', GIT_OPTIONAL_LOCKS='0',
                   GIT_CONFIG_COUNT='2', GIT_CONFIG_KEY_0='http.version',
                   GIT_CONFIG_VALUE_0='HTTP/1.1', GIT_CONFIG_KEY_1='credential.helper',
                   GIT_CONFIG_VALUE_1='')
        repositories = {}
        for identity, pin in sorted(api.dependency_pins(source).items()):
            repositories[identity] = prepare_repository(api, pin, env, receipt, known)
        api.require(sum(r['inventory']['fileCount'] for r in repositories.values()) + 3 <=
                    api.MAX_SEED_FILES and
                    sum(r['inventory']['contentBytes'] for r in repositories.values()) <=
                    api.MAX_SEED_BYTES, 'seed-total-content-budget')
        for name in api.SEED_METADATA_DIRECTORIES:
            api.require(not os.listdir(inputs / name), 'seed-preparation-metadata-not-empty')
        manifest = {'schema': 1, 'purpose': 'aetherscreens-pinned-git-inputs', 'root': str(inputs),
                    'ownerUID': os.getuid(), 'packageResolvedSHA256': api.DEPENDENCY_LOCK_SHA,
                    'preparerSHA256': args.preparer_sha256, 'workerSHA256': args.worker_sha256,
                    'sourceManifestSHA256': args.manifest_sha256,
                    'sourceArchiveSHA256': args.source_sha256, 'repositories': repositories,
                    'maximumBytes': api.MAX_SEED_BYTES, 'maximumFiles': api.MAX_SEED_FILES,
                    'metadataDirectories': sorted(api.SEED_METADATA_DIRECTORIES)}
        api.require(len(api.encoded(manifest)) <= 1024 ** 2, 'seed-manifest-byte-budget')
        api.write_exclusive(api.DEPENDENCY_MANIFEST, manifest)
        receipt.update(state='dependency-inputs-ready', exitCode=0,
                       allTenGitInputsVerified=True, manifestSHA256=api.file_hash(api.DEPENDENCY_MANIFEST))
    except api.Rejected as failure:
        receipt['state'] = str(failure)
    except KeyboardInterrupt:
        receipt['state'] = 'interrupted'
    except Exception:
        receipt['state'] = 'seed-preparation-error'
    finally:
        try:
            _, owned = api.observe(known)
            if owned != {os.getpid()}:
                receipt['stoppedOwnedProcessGroups'] += api.stop_owned(known)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                try:
                    os.waitpid(-1, os.WNOHANG)
                except ChildProcessError:
                    pass
                _, owned = api.observe(known)
                if owned == {os.getpid()}:
                    break
                time.sleep(0.2)
            receipt['ownedNetworkListeners'] = api.owned_listener_count(known)
            api.require(receipt['ownedNetworkListeners'] == 0, 'seed-owned-listener-remains')
            receipt['sourceTreeSHA256After'] = api.verify_tree(source, source_manifest)
            receipt['toolchainTreeSHA256After'] = api.verify_tree(
                api.TOOLCHAIN, tools, ignored=('toolchain-manifest.json',))
            receipt['rootOwnerSHA256After'] = api.file_hash(ROOT / '.aetherscreens-owner.json')
            receipt['workerSHA256After'] = api.file_hash(ROOT / 'macmini_headless_worker.py')
            receipt['preparerSHA256After'] = api.file_hash(Path(__file__))
            api.require(api.file_hash(api.OWNER) == args.owner_sha256 and
                        api.file_hash(ROOT / '.aetherscreens-owner.json') == root_owner_sha and
                        api.file_hash(ROOT / 'macmini_headless_worker.py') == args.worker_sha256 and
                        api.file_hash(Path(__file__)) == args.preparer_sha256 and
                        api.file_hash(api.STAGED / 'source.tgz') == args.source_sha256 and
                        api.file_hash(api.STAGED / 'source-manifest.json') == args.manifest_sha256,
                        'seed-protected-input-changed')
            receipt['treeBeforeReceipt'] = api.tree_fingerprint(inputs)
            receipt['budgetAfter'] = api.tree_fingerprint(ROOT)
            receipt['budgetAfter']['freeBytes'] = shutil.disk_usage(ROOT).free
            marker['closed'] = True
        except Exception:
            receipt.update(state='seed-terminal-closure-unverified', exitCode=2)
        receipt_path = inputs / 'prepare-receipt.json'
        api.require(len(api.encoded(receipt)) <= 128 * 1024, 'seed-receipt-byte-budget')
        api.write_exclusive(receipt_path, receipt)
        marker['evidence'] = [{'path': str(receipt_path), 'sha256': api.file_hash(receipt_path)}]
        with (inputs / api.ROUND_OWNER).open('wb') as stream:
            stream.write(api.encoded(marker))
        if receipt['exitCode'] == 0:
            try:
                api.verify_dependency_seeds(source, receipt['manifestSHA256'])
                api.budget()
            except Exception:
                receipt.update(state='seed-final-verification-failed', exitCode=2)
                with receipt_path.open('wb') as stream:
                    stream.write(api.encoded(receipt))
                marker['evidence'][0]['sha256'] = api.file_hash(receipt_path)
                with (inputs / api.ROUND_OWNER).open('wb') as stream:
                    stream.write(api.encoded(marker))
        print(json.dumps({'state': receipt['state'], 'exitCode': receipt['exitCode'],
                          'closed': marker['closed'], 'receiptSHA256': api.file_hash(receipt_path),
                          'markerSHA256': api.file_hash(inputs / api.ROUND_OWNER),
                          'manifestSHA256': receipt.get('manifestSHA256'),
                          'ownedNetworkListeners': receipt.get('ownedNetworkListeners')},
                         sort_keys=True), flush=True)
    return receipt['exitCode']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('owner-sha256', 'worker-sha256', 'preparer-sha256', 'source-sha256', 'manifest-sha256'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    api = None
    try:
        if Path(__file__).resolve() != ROOT / 'prepare_dependency_seeds.py':
            raise ValueError('preparer-path')
        pinned_tool(Path(__file__), args.preparer_sha256)
        pinned_tool(ROOT / 'macmini_headless_worker.py', args.worker_sha256)
        api = SimpleNamespace(**runpy.run_path(str(ROOT / 'macmini_headless_worker.py')))
        api.require(all(api.hash_value(value) for value in vars(args).values()), 'seed-cli-pin')
        api.host_preflight()
        api.safe_path(ROOT)
        api.require(ROOT.is_dir() and ROOT.stat().st_uid == os.getuid(), 'seed-owner-root-required')
        owner = api.pinned_json(api.OWNER, args.owner_sha256)
        api.require(owner == {'schema': 1, 'purpose': 'aetherscreens-first-release-headless-qa',
            'ownerUID': os.getuid(), 'root': str(ROOT),
            'toolchainManifestSHA256': api.TOOLCHAIN_MANIFEST_SHA}, 'seed-owner-marker')
        root_path = ROOT / '.aetherscreens-owner.json'
        root_sha = api.file_hash(root_path)
        root_owner = api.pinned_json(root_path, root_sha)
        api.require(root_owner.get('schema') == 1 and
                    root_owner.get('purpose') == 'aetherscreens-first-release-qa' and
                    root_owner.get('ownerUID') == os.getuid() and root_owner.get('root') == str(ROOT) and
                    root_owner.get('repositoryName') == 'AetherScreens' and
                    re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',
                                 root_owner.get('operationID', '')) is not None, 'seed-root-marker')
        with api.exclusive():
            api.require(not os.path.lexists(api.CURRENT), 'previous-current-must-be-closed-and-cleaned')
            api.require(not os.path.lexists(api.DEPENDENCY_INPUTS), 'dependency-input-root-exists')
            manifest = api.pinned_json(api.STAGED / 'source-manifest.json', args.manifest_sha256)
            api.validate_manifest(manifest)
            api.require(api.file_hash(api.STAGED / 'source.tgz') == args.source_sha256,
                        'seed-source-archive-pin')
            api.verify_tree(api.STAGED / 'source', manifest)
            api.dependency_pins(api.STAGED / 'source')
            tools = api.pinned_json(api.TOOLCHAIN / 'toolchain-manifest.json', api.TOOLCHAIN_MANIFEST_SHA)
            api.validate_manifest(tools, toolchain=True)
            api.verify_tree(api.TOOLCHAIN, tools, ignored=('toolchain-manifest.json',))
            api.budget()
            return prepare_locked(api, args, manifest, tools, root_sha)
    except Exception as failure:
        state = str(failure) if api is not None and isinstance(failure, api.Rejected) else 'seed-preflight-rejected'
        print(json.dumps({'state': state, 'exitCode': 2,
                          'dependencyInputRootExists': os.path.lexists(ROOT / 'dependency-inputs')},
                         sort_keys=True), flush=True)
    return 2


if __name__ == '__main__':
    sys.exit(main())
