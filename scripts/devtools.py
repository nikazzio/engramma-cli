#!/usr/bin/env python3
"""Install checksum-pinned development tools inside this checkout only."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def install(name, entry, target):
    result = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--location", "--retry", "2", entry["url"]],
        check=True, stdout=subprocess.PIPE,
    )
    archive = result.stdout
    if hashlib.sha256(archive).hexdigest() != entry["sha256"]:
        raise ValueError(f"Checksum non valido: {name}")
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as package:
        members = [m for m in package.getmembers() if m.isfile() and Path(m.name).name == name]
        if len(members) != 1:
            raise ValueError(f"Eseguibile ambiguo o assente: {name}")
        with package.extractfile(members[0]) as source:
            binary = source.read()
    target.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target, delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(binary)
            handle.flush()
            os.fchmod(handle.fileno(), 0o755)
            os.replace(temporary, target / name)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"{name}: installato e verificato")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["install"])
    parser.add_argument("tools", nargs="*", choices=["openspec", "actionlint", "gitleaks"])
    args = parser.parse_args()
    machine = {"x86_64": "x64", "aarch64": "arm64"}.get(platform.machine())
    if platform.system() != "Linux" or machine is None:
        parser.error("Gli strumenti fissati supportano Linux/WSL x64 e arm64")
    lock = json.loads((ROOT / "tools.lock.json").read_text())
    for name in args.tools or lock:
        install(name, lock[name]["platforms"][f"linux-{machine}"], ROOT / ".tools/bin")


if __name__ == "__main__":
    main()
