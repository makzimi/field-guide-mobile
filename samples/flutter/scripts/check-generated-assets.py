#!/usr/bin/env python3
"""Verify generated and optionally APK-packaged catalog bytes against canonical inputs."""
import argparse
import hashlib
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--apk', type=Path)
args = parser.parse_args()
workspace = Path(__file__).resolve().parents[1]
canonical = workspace.parent / 'contract'
generated = workspace / 'apps/field_guide/assets/generated'
expected = {'catalog-valid.json', 'catalog-changed.json', 'catalog-boundary.json', 'catalog-long-text.json', 'catalog-invalid-duplicate.json', 'catalog-invalid-enum.json'}
actual = {p.name for p in generated.glob('*.json')}
assert actual == expected, (actual, expected)
archive = zipfile.ZipFile(args.apk) if args.apk else None
try:
    for name in sorted(expected):
        source = (canonical / name).read_bytes()
        assert (generated / name).read_bytes() == source, f'Generated asset differs: {name}'
        if archive:
            key = f'assets/flutter_assets/assets/generated/{name}'
            assert archive.read(key) == source, f'APK asset differs: {key}'
        print(f'PASS {name} sha256={hashlib.sha256(source).hexdigest()} generated=identical' + (' apk=identical' if archive else ''))
finally:
    if archive:
        archive.close()
print(f'PASS {len(expected)} canonical/generated asset comparisons' + (f' and {len(expected)} APK asset comparisons' if args.apk else ''))
