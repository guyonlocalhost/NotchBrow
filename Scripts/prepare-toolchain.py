#!/usr/bin/env python3
"""Isolate stale CLT files left by in-place Apple toolchain upgrades.
Never writes outside this project's .build directory. Healthy toolchains are untouched.
"""
from pathlib import Path
import json
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
compiler = Path(subprocess.check_output(['xcrun', '-f', 'swiftc'], text=True).strip())
usr = compiler.parent.parent
work = root / '.build/toolchain'
work.mkdir(parents=True, exist_ok=True)
(work / 'compiler-path').write_text(str(compiler))
old_map = usr / 'include/swift/module.modulemap'
new_map = usr / 'include/swift/bridging.modulemap'
entries = []
if old_map.exists() and new_map.exists() and old_map.read_text().split('module SwiftBridging', 1)[-1] == new_map.read_text().split('module SwiftBridging', 1)[-1]:
    empty = work / 'empty.modulemap'
    empty.write_text('')
    entries.append({'type': 'file', 'name': str(old_map), 'external-contents': str(empty)})
manifest = usr / 'lib/swift/pm/ManifestAPI'
stale = []
for private in manifest.rglob('*.private.swiftinterface'):
    public = private.with_name(private.name.replace('.private.swiftinterface', '.swiftinterface'))
    if public.exists() and private.read_text().splitlines()[1] != public.read_text().splitlines()[1]:
        stale.append(private.relative_to(manifest))
if stale:
    local = work / 'pm/ManifestAPI'
    for link in local.rglob('*'):
        if link.is_symlink():
            link.unlink()
    shutil.copytree(manifest, local, dirs_exist_ok=True)
    for relative in stale:
        (local / relative).unlink(missing_ok=True)
(work / 'overlay.json').write_text(json.dumps({'version': 0, 'case-sensitive': False, 'roots': entries}))
print('1' if entries or stale else '0')
