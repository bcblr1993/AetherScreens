#!/usr/bin/env python3
"""Adversarial checks; all mutations and child processes are in owned temp roots."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("rotation", Path(__file__).with_name("rotate_owned_artifacts.py"))
rotation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rotation)


class RotationSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="aetherscreens-cleanup-selfcheck.")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.repo = self.base / "repository"
        self.repo.mkdir()
        (self.repo / "Package.swift").write_text("// owned fake source\n")
        (self.repo / "Package.resolved").write_text('{"pins":[]}\n')
        (self.repo / ".gitignore").write_text(".build/\nbuild/\n")
        subprocess.run(["/usr/bin/git", "init", "-q", str(self.repo)], check=True)
        self.root = self.repo / ".build"
        self.root.mkdir()
        (self.root / "products").mkdir()
        self.product = self.root / "products/product.bin"
        self.product.write_bytes(b"owned disposable product" * 100)
        self.evidence = self.base / "closed.json"
        self.evidence.write_text('{"state":"terminal","owned":true}\n')
        self.proof = self.base / "ownership.json"
        self.proof.write_bytes(rotation.encoded({"schema": 1, "purpose": rotation.PURPOSE,
            "ownerUID": os.getuid(), "root": str(self.root), "repository": str(self.repo),
            "closed": True, "evidence": [self.pin(self.evidence)]}))
        self.control = self.base / "control"
        self.request = {"schema": 1, "repository": str(self.repo),
            "roots": [{"path": str(self.root), "kind": "swift-build", "proof": self.pin(self.proof)}],
            "preserve": [self.pin(self.repo / "Package.resolved")],
            "retain": [{**self.pin(self.evidence), "slot": "latest-terminal"}],
            "nextRoundRoot": str(self.repo / "build/qa-current"),
            "maxArtifactBytes": 8 * 1024**3, "minFreeBytes": 1}
        self.request_path = self.base / "request.json"

    @staticmethod
    def pin(path):
        return {"path": str(path), "sha256": rotation.digest(path.read_bytes())}

    def prepare(self):
        raw = rotation.encoded(self.request)
        self.request_path.write_bytes(raw)
        with rotation.control_lock(self.control, create=True) as control:
            return rotation.prepare(self.request_path, rotation.digest(raw), control)

    def clean(self, apply=False, plan_sha=None):
        with rotation.control_lock(self.control) as control:
            return rotation.clean(control, apply, plan_sha)

    def rejected(self, code, action):
        with self.assertRaisesRegex(rotation.Rejected, "^" + code + "$"):
            action()
        self.assertTrue(self.product.exists())

    def test_audit_keeps_products_apply_removes_only_owned_tree_and_gate_detects_recreated_round(self):
        before_source = (self.repo / "Package.resolved").read_bytes()
        prepared = self.prepare()
        report = self.clean()
        self.assertFalse(report["deletionPerformed"])
        self.assertTrue(self.product.exists())
        report = self.clean(True, prepared["planSHA256"])
        self.assertTrue(report["deletionPerformed"])
        self.assertGreater(report["removedAllocatedBytes"], 0)
        self.assertFalse(self.root.exists())
        self.assertEqual(before_source, (self.repo / "Package.resolved").read_bytes())
        with rotation.control_lock(self.control) as control:
            self.assertTrue(rotation.gate(control)["nextRoundAllowed"])
        self.root.mkdir()
        with rotation.control_lock(self.control) as control:
            with self.assertRaisesRegex(rotation.Rejected, "previous-round-remains"):
                rotation.gate(control)

    def test_wrong_apply_sha_rejects_before_deletion(self):
        self.prepare()
        self.rejected("evidence-hash-mismatch", lambda: self.clean(True, "0" * 64))

    def test_changed_preserved_source_rejects_before_marker(self):
        (self.repo / "Package.resolved").write_text("changed")
        self.rejected("pin-hash-mismatch", self.prepare)
        self.assertFalse((self.root / rotation.OWNER).exists())

    def test_wrong_ownership_root_rejects(self):
        proof = json.loads(self.proof.read_text())
        proof["root"] = str(self.repo)
        self.proof.write_bytes(rotation.encoded(proof))
        self.request["roots"][0]["proof"] = self.pin(self.proof)
        self.rejected("ownership-attestation-rejected", self.prepare)

    def test_external_symlink_only_removes_owned_pointer_and_keeps_target(self):
        before = self.evidence.read_bytes()
        (self.root / "escape").symlink_to(self.evidence)
        prepared = self.prepare()
        self.clean(True, prepared["planSHA256"])
        self.assertEqual(self.evidence.read_bytes(), before)
        self.assertFalse(self.root.exists())

    def test_internal_symlink_is_unlinked_without_following(self):
        (self.root / "inside").symlink_to("products/product.bin")
        prepared = self.prepare()
        self.clean(True, prepared["planSHA256"])
        self.assertFalse(self.root.exists())
        self.assertTrue(self.evidence.exists())

    def test_hardlink_to_retained_evidence_rejects(self):
        os.link(self.evidence, self.root / "hardlink")
        self.rejected("unsafe-evidence-file", self.prepare)

    def test_extra_entry_since_sealing_rejects_all_deletion(self):
        prepared = self.prepare()
        (self.root / "unexpected.txt").write_text("not in sealed inventory")
        self.rejected("closed-inventory-changed", lambda: self.clean(True, prepared["planSHA256"]))

    def test_changed_product_since_sealing_rejects_all_deletion(self):
        prepared = self.prepare()
        self.product.write_bytes(b"replacement product")
        self.rejected("closed-inventory-changed", lambda: self.clean(True, prepared["planSHA256"]))

    def test_tracked_build_file_rejects_import(self):
        subprocess.run(["/usr/bin/git", "-C", str(self.repo), "add", "-f", ".build/products/product.bin"], check=True)
        self.rejected("tracked-artifact-rejected", self.prepare)

    def test_unknown_control_file_rejects(self):
        self.prepare()
        (self.control / "unknown-user-file").write_text("never prune me")
        self.rejected("unknown-control-entry", self.clean)

    def test_exclusive_producer_lock_blocks_cleaner(self):
        self.prepare()
        with rotation.control_lock(self.control):
            self.rejected("producer-or-cleaner-lock-busy", self.clean)

    def test_open_handle_blocks_cleanup_even_without_artifact_path_in_argv(self):
        prepared = self.prepare()
        program = "import os,sys,time; fd=os.open(sys.stdin.readline().strip(),os.O_RDONLY); print('ready',flush=True); time.sleep(30)"
        child = subprocess.Popen([sys.executable, "-c", program], cwd=self.base,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            child.stdin.write(str(self.product) + "\n")
            child.stdin.flush()
            self.assertEqual(child.stdout.readline().strip(), "ready")
            self.rejected("open-artifact-handles", lambda: self.clean(True, prepared["planSHA256"]))
        finally:
            child.terminate()
            child.communicate(timeout=5)

    def test_disk_budget_blocks_next_round_after_successful_cleanup(self):
        self.request["minFreeBytes"] = 2**63
        prepared = self.prepare()
        report = self.clean(True, prepared["planSHA256"])
        self.assertFalse(report["nextRoundAllowed"])
        self.assertTrue(report["deletionPerformed"])
        with rotation.control_lock(self.control) as control:
            with self.assertRaisesRegex(rotation.Rejected, "disk-budget-exceeded"):
                rotation.gate(control)


if __name__ == "__main__":
    unittest.main()
