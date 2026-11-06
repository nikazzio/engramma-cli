"""Validate release privacy, reproducibility and development-tool integrity."""

import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = module("package")
        self.package.ROOT = self.root
        (self.root / "VERSION").write_text("0.1.0-alpha.1\n")
        (self.root / "README.md").write_text("Example\n")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def track(self):
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)

    def build(self):
        with patch("sys.stdout", new=io.StringIO()):
            self.package.main()
        return self.root / "dist/engramma-0.1.0-alpha.1.tar.gz"

    def test_private_data_is_excluded_even_if_tracked(self):
        for name in ("workspaces/customer/memory.txt", "global/settings.json", "skills/private/note.md", ".env"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("private data")
        self.track()
        with tarfile.open(self.build()) as archive:
            names = archive.getnames()
            self.assertEqual(len(names), 2)
            self.assertTrue(all(Path(name).name in {"VERSION", "README.md"} for name in names))

    def test_distribution_is_reproducible_and_checksum_matches(self):
        self.track()
        first = self.build().read_bytes()
        os.utime(self.root / "README.md", (1, 1))
        self.assertEqual(first, self.build().read_bytes())
        expected = hashlib.sha256(first).hexdigest()
        self.assertEqual((self.root / "dist/SHA256SUMS").read_text().split()[0], expected)

    def test_symlinks_cannot_import_external_contents(self):
        (self.root / "bin").mkdir()
        (self.root / "bin/external").symlink_to(ROOT / "VERSION")
        self.track()
        with self.assertRaises(ValueError):
            self.build()


class DevelopmentToolTests(unittest.TestCase):
    def test_checksum_failure_never_installs_a_tool(self):
        installer = module("devtools")
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "bin"
            result = subprocess.CompletedProcess([], 0, stdout=b"altered download")
            with patch.object(installer.subprocess, "run", return_value=result):
                with self.assertRaises(ValueError):
                    installer.install("openspec", {"url": "https://example.test/tool", "sha256": "0" * 64}, target)
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
