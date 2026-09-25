#!/usr/bin/env python3
"""Exercise the real updater helper against disposable copies, never /Applications."""
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
old = pathlib.Path('/Applications/NotchBrow.app')
new = root / 'build/NotchBrow.app'
def info(app):
    return plistlib.loads((app / 'Contents/Info.plist').read_bytes())

with tempfile.TemporaryDirectory(prefix='NotchBrow-install-test-') as temporary:
    folder = pathlib.Path(temporary)
    target = folder / 'NotchBrow.app'
    stage = folder / '.NotchBrow-update-test.app'
    backup = folder / '.NotchBrow-backup-test.app'
    work = folder / 'work'
    work.mkdir()
    subprocess.run(['/usr/bin/ditto', str(old), str(target)], check=True)
    subprocess.run(['/usr/bin/ditto', str(new), str(stage)], check=True)
    prior = info(old)
    release = info(new)
    # The isolated target needs an older build number even after the real app is updated.
    if int(prior['CFBundleVersion']) >= int(release['CFBundleVersion']):
        prior['CFBundleVersion'] = str(int(release['CFBundleVersion']) - 1)
        (target / 'Contents/Info.plist').write_bytes(plistlib.dumps(prior))
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(target)], check=True)
    helper = work / 'installer'
    shutil.copy2(new / 'Contents/MacOS/NotchBrow', helper)
    parent = subprocess.Popen(['/bin/sleep', '120'])
    job = dict(target=target.as_uri(), staged=stage.as_uri(), backup=backup.as_uri(),
               parentPID=parent.pid, previousBuild=int(prior['CFBundleVersion']),
               build=int(release['CFBundleVersion']), version=release['CFBundleShortVersionString'])
    job_file = work / 'install.json'
    job_file.write_text(json.dumps(job))
    installer = subprocess.Popen([str(helper), '--install-update', str(job_file)])
    try:
        deadline = time.monotonic() + 15
        while not (work / 'ready').exists() and time.monotonic() < deadline:
            if installer.poll() is not None:
                raise AssertionError((work / 'failure.txt').read_text())
            time.sleep(.1)
        assert (work / 'ready').exists(), 'Installer did not prepare'
        assert info(target)['CFBundleVersion'] == prior['CFBundleVersion'], 'Modified app before quit'
        print('PASS: Real helper validates and waits for the running app to quit', flush=True)
        parent.terminate(); parent.wait()
        assert installer.wait(timeout=45) == 0, (work / 'failure.txt').read_text()
        assert info(target)['CFBundleVersion'] == release['CFBundleVersion']
        assert not backup.exists() and not stage.exists() and not work.exists()
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(target)], check=True)
        print('PASS: Real helper replaces, launches, receives startup acknowledgment, and cleans up', flush=True)
    finally:
        if parent.poll() is None:
            parent.terminate(); parent.wait()
        if installer.poll() is None:
            installer.terminate(); installer.wait()
        # Only the disposable app launched by this test, never the installed app.
        subprocess.run(['/usr/bin/pkill', '-f', re.escape(str(target / 'Contents/MacOS/NotchBrow'))], check=False)
