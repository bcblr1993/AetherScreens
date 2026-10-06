#!/usr/bin/env python3
"""Seal and prune closed AetherScreens QA artifacts, with no automatic discovery.

prepare --request FILE --request-sha256 SHA --control DIR imports explicitly
reviewed ownership receipts and writes one closed inventory. clean --control DIR
is read-only by default; add --apply --plan-sha256 SHA to delete that inventory.
gate --control DIR must pass before the next test. The next output directory is
always the request's fixed nextRoundRoot; a previous round must be removed first.

An ownership receipt has schema=1, purpose="aetherscreens-qa-artifacts",
ownerUID, root, repository, closed=true, and evidence=[{path, sha256}]. It is an
explicit ownership attestation backed by saved receipts, not inferred from a
directory name. The caller supplies its reviewed SHA in the request. Producers
must use the control marker's advisory lock; this tool never stops a process.
See --help for the request schema. No external package, SSH, cache purge, simulator
operation, source edit, or backup of large artifacts is performed.
"""
import argparse
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time

OWNER = ".aetherscreens-artifact-owner.json"
CONTROL_OWNER = ".aetherscreens-cleanup-owner.json"
PURPOSE = "aetherscreens-qa-artifacts"
FIXED_FILES = {CONTROL_OWNER, "pending-plan.json", "inventory.json",
               "last-cleanup.json", "retained-evidence.json"}
WORKERS = {"xcodebuild", "xctest", "XCTRunner", "swift", "swift-build",
           "swift-test", "swiftc", "swift-frontend", "xcodegen", "UIRunner"}
MAX_JSON = 256 * 1024 * 1024
MAX_RETAIN = 1024 * 1024
COMMAND_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C",
               "PYTHONDONTWRITEBYTECODE": "1"}


class Rejected(Exception):
    pass


def require(value, code):
    if not value:
        raise Rejected(code)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate-json-key")
        result[key] = value
    return result


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def hash_value(value):
    return isinstance(value, str) and re.fullmatch("[0-9a-f]{64}", value) is not None


def below(path, root):
    return path == root or root in path.parents


def canonical(value):
    require(isinstance(value, str) and value.startswith("/") and
            not any(ord(c) < 32 for c in value), "absolute-path-required")
    path = Path(value)
    require(str(path) == value and os.path.abspath(value) == value, "noncanonical-path")
    for part in list(reversed(path.parents)) + [path]:
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode), "symlink-ancestor")
    require(path.resolve() == path, "path-escape")
    return path


def file_bytes(path, maximum=MAX_JSON):
    path = canonical(str(path))
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and
                info.st_nlink == 1 and info.st_size <= maximum, "unsafe-evidence-file")
        with os.fdopen(os.dup(descriptor), "rb") as stream:
            data = stream.read(maximum + 1)
        after = os.fstat(descriptor)
        require(len(data) == info.st_size and identity(info) == identity(after),
                "evidence-file-changed")
        return data
    finally:
        os.close(descriptor)


def json_file(path, expected=None, maximum=MAX_JSON):
    raw = file_bytes(path, maximum)
    if expected is not None:
        require(hash_value(expected) and digest(raw) == expected, "evidence-hash-mismatch")
    try:
        return json.loads(raw, object_pairs_hook=unique), raw
    except (ValueError, UnicodeError):
        raise Rejected("invalid-json")


def identity(info):
    return [info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns]


def command(argv, accepted=(0,)):
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=COMMAND_ENV, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        raise Rejected("activity-query-unavailable")
    require(result.returncode in accepted and not result.stderr.strip(),
            "activity-query-rejected")
    return result


def worktree(repository):
    result = command(["/usr/bin/git", "-C", str(repository), "rev-parse", "--show-toplevel"])
    require(result.stdout.decode().strip() == str(repository), "worktree-mismatch")


def check_root(root, kind, repository):
    require(root.exists() and root.is_dir() and root.lstat().st_uid == os.getuid(),
            "artifact-root-unavailable")
    require(root != repository and not below(repository, root), "source-root-protected")
    q34 = repository / "build/shipping-owned-generator-path-qa"
    require(not below(root, q34) and not below(q34, root), "qa34-evidence-protected")
    if kind == "swift-build":
        require(root == repository / ".build", "swift-build-path-rejected")
        worktree(repository)
        result = command(["/usr/bin/git", "-C", str(repository), "ls-files", "-z", "--", ".build"])
        require(not result.stdout, "tracked-artifact-rejected")
        result = command(["/usr/bin/git", "-C", str(repository), "check-ignore", "--", ".build"])
        require(result.stdout.strip() == b".build", "unignored-build-rejected")
    else:
        require(kind == "qa-round", "artifact-kind-rejected")
        build = repository / "build"
        home = Path(os.path.expanduser("~"))
        home_parts = root.relative_to(home).parts if below(root, home) else ()
        require((below(root, build) and root != build) or
                (home_parts and re.fullmatch(r"aetherscreens-[a-z0-9.-]+", home_parts[0])),
                "qa-root-scope-rejected")


def pinned(record):
    require(isinstance(record, dict) and set(record) == {"path", "sha256"}, "pin-schema")
    path = canonical(record["path"])
    raw = file_bytes(path)
    require(hash_value(record["sha256"]) and digest(raw) == record["sha256"], "pin-hash-mismatch")
    return path, raw


def preserve(request):
    pins = request["preserve"]
    require(isinstance(pins, list) and 1 <= len(pins) <= 1024, "preserve-schema")
    seen = set()
    for pin in pins:
        path, _ = pinned(pin)
        require(path not in seen, "duplicate-preserve-pin")
        seen.add(path)
    repository = Path(request["repository"])
    require(repository / "Package.resolved" in seen, "package-pins-preservation-required")
    q34 = repository / "build/shipping-owned-generator-path-qa"
    if q34.exists():
        for name in ["source-manifest.json", "source.tgz", "vm-native-generation-only-verified.json"]:
            require(q34 / name in seen, "qa34-preservation-pins-required")
        manifest, _ = json_file(q34 / "source-manifest.json")
        require(isinstance(manifest, dict) and len(manifest) == 245, "qa34-manifest-schema")
        frozen = q34 / "frozen-production-source"
        actual = set()
        for parent, directories, files in os.walk(frozen, followlinks=False):
            for name in directories + files:
                p = Path(parent) / name
                require(not p.is_symlink(), "qa34-frozen-symlink")
            for name in files:
                path = Path(parent) / name
                relative = path.relative_to(frozen).as_posix()
                require(relative in manifest and digest(file_bytes(path)) == manifest[relative],
                        "qa34-frozen-source-changed")
                actual.add(relative)
        require(actual == set(manifest), "qa34-frozen-source-set-changed")
    return seen


def ownership(item, repository):
    require(set(item) == {"path", "kind", "proof"}, "root-request-schema")
    root = canonical(item["path"])
    check_root(root, item["kind"], repository)
    proof_path, proof_raw = pinned(item["proof"])
    proof = json.loads(proof_raw, object_pairs_hook=unique)
    fields = {"schema", "purpose", "ownerUID", "root", "repository", "closed", "evidence"}
    require(isinstance(proof, dict) and set(proof) == fields and proof["schema"] == 1 and
            proof["purpose"] == PURPOSE and proof["ownerUID"] == os.getuid() and
            proof["root"] == str(root) and proof["repository"] == str(repository) and
            proof["closed"] is True, "ownership-attestation-rejected")
    require(isinstance(proof["evidence"], list) and 1 <= len(proof["evidence"]) <= 32,
            "ownership-evidence-required")
    anchors = [proof_path]
    for pin in proof["evidence"]:
        path, _ = pinned(pin)
        anchors.append(path)
    return root, anchors


def inventory(root):
    entries = {}
    root_stat = root.lstat()
    require(not root.is_symlink() and stat.S_ISDIR(root_stat.st_mode), "unsafe-root")
    def visit(directory):
        with os.scandir(directory) as stream:
            children = sorted(stream, key=lambda entry: entry.name)
        for child in children:
            path = directory / child.name
            if path == root / OWNER:
                continue
            relative = path.relative_to(root).as_posix()
            info = child.stat(follow_symlinks=False)
            require(info.st_dev == root_stat.st_dev and info.st_uid == os.getuid(),
                    "foreign-or-cross-device-entry")
            row = {"identity": identity(info), "allocatedBytes": info.st_blocks * 512}
            if stat.S_ISDIR(info.st_mode):
                row["kind"] = "directory"
                entries[relative] = row
                visit(path)
            elif stat.S_ISREG(info.st_mode):
                require(info.st_nlink == 1, "hardlinked-artifact-rejected")
                descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                try:
                    require(identity(os.fstat(descriptor)) == identity(info), "artifact-changed")
                    hasher = hashlib.sha256()
                    with os.fdopen(os.dup(descriptor), "rb") as stream:
                        for block in iter(lambda: stream.read(1024 * 1024), b""):
                            hasher.update(block)
                    require(identity(os.fstat(descriptor)) == identity(info), "artifact-changed")
                    row.update(kind="file", sha256=hasher.hexdigest())
                finally:
                    os.close(descriptor)
                entries[relative] = row
            elif stat.S_ISLNK(info.st_mode):
                target = os.readlink(path)
                # Seal the owned pointer itself. Never resolve, stat, read, or
                # recurse into its target, including external/dangling links.
                row.update(kind="symlink", target=target)
                entries[relative] = row
            else:
                raise Rejected("special-artifact-entry")
    visit(root)
    marker_bytes = (root / OWNER).lstat().st_blocks * 512 if (root / OWNER).exists() else 0
    return {"rootIdentity": identity(root_stat), "entries": entries,
            "allocatedBytes": root_stat.st_blocks * 512 + marker_bytes +
                              sum(r["allocatedBytes"] for r in entries.values())}


def activity(roots):
    result = command(["/bin/ps", "-axo", "pid=,comm=,args="])
    for line in result.stdout.decode("utf-8", "strict").splitlines():
        parts = line.strip().split(None, 2)
        require(len(parts) >= 2 and parts[0].isdigit(), "process-schema-rejected")
        if int(parts[0]) == os.getpid():
            continue
        name = parts[1].rsplit("/", 1)[-1]
        require(name not in WORKERS and not name.endswith("UITests-Runner"), "active-test-worker")
        arguments = parts[2] if len(parts) == 3 else ""
        require(not any(re.search(re.escape(str(root)) + r"(?:[/\s]|$)", arguments)
                        or below(Path(parts[1]), root) for root in roots), "active-artifact-process")
    for root in roots:
        # Positive self probe prevents interpreting an ineffective scanner as idle.
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            probe = command(["/usr/sbin/lsof", "+w", "-a", "-p", str(os.getpid()),
                             "-F0pn", str(root)], accepted=(0,))
            require(b"n" + os.fsencode(root) + b"\0" in probe.stdout,
                    "open-handle-scanner-unconfirmed")
            result = command(["/usr/sbin/lsof", "+w", "-a", "-p", "^" + str(os.getpid()),
                              "-F0pfnt", "+D", str(root)], accepted=(0, 1))
            require(result.returncode == 1 and not result.stdout, "open-artifact-handles")
        finally:
            os.close(descriptor)


def write_fixed(control, name, data):
    require(name in FIXED_FILES and len(data) <= MAX_JSON, "control-file-rejected")
    target = control / name
    if target.exists():
        file_bytes(target)
    temporary = control / (name + ".new")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()


@contextmanager
def control_lock(path, create=False):
    control = canonical(str(path))
    if not control.exists():
        require(create and control.parent.is_dir(), "control-unavailable")
        control.mkdir(mode=0o700)
        data = encoded({"schema": 1, "purpose": PURPOSE, "ownerUID": os.getuid(), "control": str(control)})
        write_fixed(control, CONTROL_OWNER, data)
    require(control.is_dir() and control.lstat().st_uid == os.getuid(), "control-owner-rejected")
    require(set(p.name for p in control.iterdir()) <= FIXED_FILES, "unknown-control-entry")
    marker, _ = json_file(control / CONTROL_OWNER)
    require(marker == {"schema": 1, "purpose": PURPOSE, "ownerUID": os.getuid(), "control": str(control)},
            "control-marker-rejected")
    descriptor = os.open(control / CONTROL_OWNER, os.O_RDWR | os.O_NOFOLLOW)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Rejected("producer-or-cleaner-lock-busy")
        yield control
    finally:
        os.close(descriptor)


def validate_request(request):
    fields = {"schema", "repository", "roots", "preserve", "retain", "nextRoundRoot",
              "maxArtifactBytes", "minFreeBytes"}
    require(isinstance(request, dict) and set(request) == fields and request["schema"] == 1,
            "request-schema")
    repository = canonical(request["repository"])
    require(repository.is_dir() and (repository / "Package.swift").is_file(), "repository-unavailable")
    require(isinstance(request["roots"], list) and 1 <= len(request["roots"]) <= 64, "roots-schema")
    require(isinstance(request["retain"], list) and len(request["retain"]) <= 32, "retain-schema")
    for key in ["maxArtifactBytes", "minFreeBytes"]:
        require(type(request[key]) is int and request[key] > 0, "disk-budget-required")
    next_root = canonical(request["nextRoundRoot"])
    home = Path(os.path.expanduser("~"))
    home_parts = next_root.relative_to(home).parts if below(next_root, home) else ()
    require(next_root == repository / "build/qa-current" or
            (len(home_parts) >= 2 and next_root.name == "current" and
             re.fullmatch(r"aetherscreens-[a-z0-9.-]+", home_parts[0])), "fixed-next-round-required")
    return repository


def prepare(request_path, expected, control):
    require(not (control / "pending-plan.json").exists() and not (control / "inventory.json").exists(),
            "previous-plan-must-be-cleaned")
    request, request_raw = json_file(request_path, expected)
    repository = validate_request(request)
    pins = preserve(request)
    roots, anchors = [], []
    for item in request["roots"]:
        root, evidence = ownership(item, repository)
        roots.append(root)
        anchors.extend(evidence)
    require(len(set(roots)) == len(roots) and all(not below(a, b) for a in roots for b in roots if a != b),
            "overlapping-artifact-roots")
    require(all(not below(control, r) and not below(r, control) for r in roots), "control-overlap")
    proof_paths = [canonical(item["proof"]["path"]) for item in request["roots"]]
    require(all(not below(p, r) for p in list(pins) + proof_paths + [canonical(str(request_path))] for r in roots),
            "preserved-evidence-overlap")
    retain = retain_records(request)
    retained_paths = {Path(item["path"]) for item in request["retain"]}
    require(all(not below(p, r) or p in retained_paths for p in anchors for r in roots),
            "ownership-receipt-retention-required")
    plan_roots, inventories = [], {}
    activity(roots)
    # Validate all trees before adding any ownership marker.
    for root in roots:
        require(not os.path.lexists(root / OWNER), "already-marked-root")
        inventories[str(root)] = inventory(root)
    request_sha = digest(encoded(request))
    for item, root in zip(request["roots"], roots):
        marker = {"schema": 1, "purpose": PURPOSE, "ownerUID": os.getuid(), "root": str(root),
                  "repository": str(repository), "kind": item["kind"], "requestSHA256": request_sha,
                  "rootDevice": root.lstat().st_dev, "rootInode": root.lstat().st_ino,
                  "ownershipProofSHA256": item["proof"]["sha256"]}
        raw = encoded(marker)
        descriptor = os.open(root / OWNER, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(raw)
        # Marker creation changes root metadata, so capture that final root identity.
        inventories[str(root)]["rootIdentity"] = identity(root.lstat())
        inventories[str(root)]["allocatedBytes"] += (root / OWNER).lstat().st_blocks * 512
        plan_roots.append({"path": str(root), "markerSHA256": digest(raw)})
    inventory_raw = encoded(inventories)
    require(len(inventory_raw) <= MAX_JSON, "inventory-too-large")
    plan = {"schema": 1, "request": request, "requestSHA256": request_sha, "roots": plan_roots,
            "inventorySHA256": digest(inventory_raw), "retainedSHA256": digest(encoded(retain))}
    write_fixed(control, "inventory.json", inventory_raw)
    plan_raw = encoded(plan)
    write_fixed(control, "pending-plan.json", plan_raw)
    return {"state": "owned-artifacts-sealed", "planSHA256": digest(plan_raw), "rootCount": len(roots),
            "allocatedBytes": sum(i["allocatedBytes"] for i in inventories.values()),
            "deletionPerformed": False, "nextRoundAllowed": False}


def retain_records(request):
    records, slots, total = [], set(), 0
    for item in request["retain"]:
        require(isinstance(item, dict) and set(item) == {"path", "sha256", "slot"} and
                isinstance(item["slot"], str) and re.fullmatch(r"[a-z0-9-]{1,64}", item["slot"]),
                "retain-record-schema")
        require(item["slot"] not in slots, "duplicate-retain-slot")
        slots.add(item["slot"])
        path, raw = pinned({"path": item["path"], "sha256": item["sha256"]})
        total += len(raw)
        require(len(raw) <= 128 * 1024 and total <= MAX_RETAIN, "retained-evidence-budget-exceeded")
        records.append({"slot": item["slot"], "originalPath": str(path), "sha256": item["sha256"],
                        "contentBase64": base64.b64encode(raw).decode("ascii")})
    return {"schema": 1, "records": records}


def delete_tree(root, expected):
    parent_fd = os.open(root.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    root_fd = os.open(root.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
    try:
        require(identity(os.fstat(root_fd)) == expected["rootIdentity"], "root-identity-changed")
        entries = expected["entries"]
        children = {}
        for key in entries:
            parent, _, name = key.rpartition("/")
            children.setdefault(parent, set()).add(name)
        def remove(directory_fd, relative):
            expected_names = children.get(relative, set())
            actual_names = set(os.listdir(directory_fd))
            if not relative:
                actual_names.discard(OWNER)
            require(actual_names == expected_names, "artifact-directory-set-changed")
            for name in sorted(expected_names):
                key = relative + "/" + name if relative else name
                row = entries[key]
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                require(identity(info) == row["identity"], "artifact-entry-identity-changed")
                if row["kind"] == "directory":
                    child_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory_fd)
                    try:
                        require(identity(os.fstat(child_fd)) == row["identity"], "artifact-directory-changed")
                        remove(child_fd, key)
                    finally:
                        os.close(child_fd)
                    require(os.stat(name, dir_fd=directory_fd, follow_symlinks=False).st_ino == info.st_ino,
                            "artifact-directory-replaced")
                    os.rmdir(name, dir_fd=directory_fd)
                else:
                    if row["kind"] == "symlink":
                        require(os.readlink(name, dir_fd=directory_fd) == row["target"], "artifact-link-changed")
                    os.unlink(name, dir_fd=directory_fd)
            require(set(os.listdir(directory_fd)) == ({OWNER} if not relative else set()),
                    "late-artifact-entry")
        remove(root_fd, "")
        os.unlink(OWNER, dir_fd=root_fd)
        require(not os.listdir(root_fd), "root-not-empty")
        require(os.stat(root.name, dir_fd=parent_fd, follow_symlinks=False).st_ino == os.fstat(root_fd).st_ino,
                "root-replaced")
        os.rmdir(root.name, dir_fd=parent_fd)
    finally:
        os.close(root_fd)
        os.close(parent_fd)


def allocated_tree(root):
    total = 0
    if not root.exists():
        return 0
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            total += (Path(parent) / name).lstat().st_blocks * 512
    return total + root.lstat().st_blocks * 512


def budget(request, control):
    repository = Path(request["repository"])
    artifact_bytes = allocated_tree(repository / ".build") + allocated_tree(repository / "build")
    # External explicitly attested roots also count, with no follow or deletion.
    for item in request["roots"]:
        root = Path(item["path"])
        if not below(root, repository):
            artifact_bytes += allocated_tree(root)
    next_root = Path(request["nextRoundRoot"])
    if not below(next_root, repository):
        # Budget the fixed remote workspace including tools/cache siblings.
        artifact_bytes += allocated_tree(next_root.parent)
    free = os.statvfs(control).f_bavail * os.statvfs(control).f_frsize
    return {"artifactBytesAfter": artifact_bytes, "maxArtifactBytes": request["maxArtifactBytes"],
            "freeBytesAfter": free, "minFreeBytes": request["minFreeBytes"],
            "diskBudgetPassed": artifact_bytes <= request["maxArtifactBytes"] and free >= request["minFreeBytes"]}


def clean(control, apply=False, expected=None):
    require(not apply or hash_value(expected), "apply-plan-hash-required")
    plan, plan_raw = json_file(control / "pending-plan.json", expected)
    require(set(plan) == {"schema", "request", "requestSHA256", "roots", "inventorySHA256", "retainedSHA256"}
            and plan["schema"] == 1, "plan-schema")
    request = plan["request"]
    repository = validate_request(request)
    require(digest(encoded(request)) == plan["requestSHA256"] and
            len(plan["roots"]) == len(request["roots"]), "request-plan-binding")
    preserve(request)
    inventories, _ = json_file(control / "inventory.json", plan["inventorySHA256"])
    require(set(inventories) == {item["path"] for item in plan["roots"]}, "inventory-root-set")
    roots = [canonical(item["path"]) for item in plan["roots"]]
    for item, root, requested in zip(plan["roots"], roots, request["roots"]):
        require(item["path"] == requested["path"], "plan-root-binding")
        ownership(requested, repository)
        marker, raw = json_file(root / OWNER, item["markerSHA256"])
        require(set(marker) == {"schema", "purpose", "ownerUID", "root", "repository", "kind", "requestSHA256",
                               "rootDevice", "rootInode", "ownershipProofSHA256"} and marker["schema"] == 1 and
                marker["root"] == str(root) and marker["repository"] == str(repository) and
                marker["purpose"] == PURPOSE and marker["ownerUID"] == os.getuid() and
                marker["kind"] == requested["kind"] and
                marker["ownershipProofSHA256"] == requested["proof"]["sha256"] and
                marker["requestSHA256"] == plan["requestSHA256"] and
                marker["rootDevice"] == root.lstat().st_dev and marker["rootInode"] == root.lstat().st_ino,
                "artifact-marker-binding")
        require(inventory(root) == inventories[str(root)], "closed-inventory-changed")
    retained = retain_records(request)
    require(digest(encoded(retained)) == plan["retainedSHA256"], "retained-evidence-changed")
    activity(roots)
    report = {"state": "owned-artifact-cleanup-audited", "planSHA256": digest(plan_raw),
              "rootCount": len(roots), "allocatedBytesToRemove": sum(i["allocatedBytes"] for i in inventories.values()),
              "deletionPerformed": False, "nextRoundAllowed": False}
    if not apply:
        return report
    # Small fixed evidence is retained before the first deletion; no large backup.
    write_fixed(control, "retained-evidence.json", encoded(retained))
    preserve(request)
    activity(roots)
    for root in roots:
        # The fresh content hashes above are followed by activity checks and a
        # per-entry dev/ino/mode/uid/nlink/size/mtime/ctime check at deletion.
        delete_tree(root, inventories[str(root)])
    preserve(request)
    require(all(not os.path.lexists(root) for root in roots), "deletion-not-confirmed")
    report.update(state="owned-artifacts-removed", deletionPerformed=True,
                  removedAllocatedBytes=report["allocatedBytesToRemove"], retainedEvidenceBytes=len(encoded(retained)),
                  retainedEvidenceSHA256=digest(encoded(retained)), retainedEvidenceCount=len(retained["records"]),
                  protectedSourceAndQA34Verified=True, request=request, **budget(request, control))
    report["nextRoundAllowed"] = report["diskBudgetPassed"] and not Path(request["nextRoundRoot"]).exists()
    write_fixed(control, "last-cleanup.json", encoded(report))
    (control / "inventory.json").unlink()
    (control / "pending-plan.json").unlink()
    return {k: v for k, v in report.items() if k != "request"}


def gate(control):
    require(not (control / "pending-plan.json").exists() and not (control / "inventory.json").exists(),
            "previous-round-not-cleaned")
    previous, _ = json_file(control / "last-cleanup.json")
    require(previous.get("state") == "owned-artifacts-removed" and previous.get("deletionPerformed") is True,
            "verified-cleanup-required")
    request = previous["request"]
    validate_request(request)
    preserve(request)
    json_file(control / "retained-evidence.json", previous["retainedEvidenceSHA256"])
    repository = Path(request["repository"])
    require(not os.path.lexists(repository / ".build") and
            not os.path.lexists(request["nextRoundRoot"]) and
            all(not os.path.lexists(item["path"]) for item in request["roots"]), "previous-round-remains")
    result = budget(request, control)
    require(result["diskBudgetPassed"], "disk-budget-exceeded")
    return {"state": "ready-for-one-round", "nextRoundAllowed": True,
            "nextRoundRoot": request["nextRoundRoot"], **result}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='Request keys: schema=1, repository, roots=[{path,kind="swift-build"|"qa-round",proof={path,sha256}}],\n'
               'preserve=[{path,sha256}], retain=[{path,sha256,slot}], nextRoundRoot="REPO/build/qa-current",\n'
               'nextRoundRoot may also be HOME/aetherscreens-*/.../current (fixed remote root).\n'
               'maxArtifactBytes, minFreeBytes. Preserve Package.resolved and the three QA34 proof/archive pins.\n'
               'Only explicit roots are removed. All producers must hold an exclusive flock on CONTROL/' + CONTROL_OWNER + '.')
    parser.add_argument("action", choices=["prepare", "clean", "gate"])
    parser.add_argument("--control", required=True, type=Path)
    parser.add_argument("--request", type=Path)
    parser.add_argument("--request-sha256")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        require(sys.platform == "darwin", "macos-required")
        require(args.action == "clean" or not args.apply, "apply-action-rejected")
        with control_lock(args.control, create=args.action == "prepare") as control:
            if args.action == "prepare":
                require(args.request is not None and hash_value(args.request_sha256), "reviewed-request-required")
                result = prepare(args.request, args.request_sha256, control)
            elif args.action == "clean":
                result = clean(control, args.apply, args.plan_sha256)
            else:
                result = gate(control)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (Rejected, OSError, ValueError, KeyError, UnicodeError) as failure:
        code = str(failure) if isinstance(failure, Rejected) else "cleanup-driver-error"
        print(json.dumps({"state": code, "exitCode": 2, "nextRoundAllowed": False,
                          "partialDeletionPossible": args.action == "clean" and args.apply}, sort_keys=True))
        return 2


if __name__ == "__main__":
    sys.exit(main())
