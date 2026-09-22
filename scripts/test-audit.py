#!/usr/bin/env python3
"""Exercise privacy audit failure paths in an isolated synthetic Git repository."""
import pathlib
import shutil
import subprocess
import tempfile

source = pathlib.Path(__file__).with_name('audit-source.py')
with tempfile.TemporaryDirectory(prefix='avakasha-audit-test-') as folder:
    root = pathlib.Path(folder)
    (root / 'scripts').mkdir()
    shutil.copyfile(source, root / 'scripts/audit-source.py')
    def git(*args):
        return subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
    def audit(ok):
        result = subprocess.run(['python3', 'scripts/audit-source.py'], cwd=root, capture_output=True)
        assert (result.returncode == 0) == ok, 'Unexpected audit result'
    git('init', '-q'); git('config','user.name','Synthetic test');git('config','user.email','test@example.invalid')
    audit(False)  # Empty index must not pass.
    git('add','.');audit(True)
    payload=root/'fixture.txt';payload.write_text('ghp_'+'A'*32)
    git('add','.');audit(False)
    git('commit','-qm','Synthetic credential detection fixture')
    payload.unlink();git('add','-u');git('commit','-qm','Remove fixture')
    audit(False)  # Deleted credentials still exist in history.
print('Privacy audit regression passed: empty index, clean source, staged credential, historical credential.')
