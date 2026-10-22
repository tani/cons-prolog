#!/usr/bin/env python3
"""Fetch the two hash-pinned Hodgson distributions without vendoring them."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request

LOCK = json.loads((Path(__file__).parent / "upstream.json").read_text())


def validate(root):
    for name, archive in LOCK["archives"].items():
        directory = root / name
        actual = {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(directory.rglob("*")) if p.is_file()}
        if actual != archive["files"]:
            raise ValueError("Upstream files differ from the pinned distribution: " + name)


def fetch(root):
    for name, archive in LOCK["archives"].items():
        with urllib.request.urlopen(archive["url"], timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != archive["sha256"]:
            raise ValueError("Archive digest mismatch: " + name)
        directory = (root / name).resolve()
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as source:
            for member in source:
                if member.isdir():
                    continue
                target = directory / member.name
                if (not member.isfile() or not target.resolve().is_relative_to(directory)
                        or member.name not in archive["files"]):
                    raise ValueError("Unexpected archive member: " + member.name)
                content = source.extractfile(member).read()
                if hashlib.sha256(content).hexdigest() != archive["files"][member.name]:
                    raise ValueError("Member digest mismatch: " + member.name)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
    validate(root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    fetch(args.output)
