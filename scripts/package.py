#!/usr/bin/env python3
"""Build a deterministic source distribution from an explicit tracked allowlist."""

import gzip
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = {"bin", "lib", "completions", "docs", "tests", "scripts", "examples", ".github"}
FILES = {"README.md", "LICENSE", "VERSION", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md", "AGENTS.md", "Makefile", "tools.lock.json", "zensical.toml", ".shellcheckrc", ".editorconfig", ".gitattributes", ".gitignore"}


def main():
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("VERSION non valida")
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    paths = []
    for name in sorted(filter(None, tracked)):
        relative = Path(name)
        if relative.parts[0] in DIRECTORIES or name in FILES:
            path = ROOT / relative
            if path.is_symlink() or not path.is_file():
                raise ValueError(f"File non regolare nella distribuzione: {relative}")
            paths.append(path)
    if not paths:
        raise ValueError("Nessun file versionato da distribuire")
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    filename = f"engramma-{version}.tar.gz"
    temporary = output / (filename + ".tmp")
    try:
        with temporary.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(mode="w", fileobj=compressed, format=tarfile.PAX_FORMAT) as archive:
                for path in paths:
                    member = archive.gettarinfo(str(path), arcname=f"engramma-{version}/{path.relative_to(ROOT)}")
                    member.uid = member.gid = member.mtime = 0
                    member.uname = member.gname = ""
                    member.mode = 0o755 if os.access(path, os.X_OK) else 0o644
                    with path.open("rb") as handle:
                        archive.addfile(member, handle)
        temporary.replace(output / filename)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256((output / filename).read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(f"{digest}  {filename}\n")
    print(f"Creati dist/{filename} e dist/SHA256SUMS")


if __name__ == "__main__":
    main()
