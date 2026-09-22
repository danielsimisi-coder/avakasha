#!/usr/bin/env python3
"""Audit tracked source and every reachable Git blob; report locations, never secret values."""
import hashlib
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
artwork = {
    'assets/keepelix-preview.png': 'de27146eec2287094fd61eda87be6806c34399f2c6c98250e85370486f0882fc',
    'assets/keepelix-older-files.png': '4e51d5dfa9610f64fdbd84e1df64132fe943768897bf53fb57ef5245f505e2f4',
    'assets/icon-1024.png': '95ff2ed3079abdc2143948ec1586c53a19fbdeb30ecbefa06d37c99f2129531b',
    'assets/AppIcon.icns': '9f603b3652db574dae84fa3b67f738a1455618a58590204bdee54be5f574dc97',
}
failures = []
patterns = [
    (rb'/Users/[A-Za-z0-9_][^/\s]*/', 'machine-specific home path'),
    (rb'(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_]{16,}', 'possible credential'),
    (rb'AKIA[0-9A-Z]{16}', 'possible cloud credential'),
    (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', 'private key'),
]

def check(relative, data, label):
    path = pathlib.PurePosixPath(relative)
    if path.name in {'media.json', 'auth.json', '.env'} or path.name.startswith('.env.') or path.suffix.lower() in {'.sqlite', '.db', '.p12', '.pem', '.zip', '.csv', '.mp4', '.mov', '.jpg', '.jpeg', '.pdf'}:
        failures.append(label + ': private payload type')
    if relative in artwork:
        if hashlib.sha256(data).hexdigest() != artwork[relative]:
            failures.append(label + ': artwork differs from reviewed synthetic asset')
        return
    if b'\x00' in data:
        failures.append(label + ': unexpected binary')
        return
    for pattern, reason in patterns:
        if re.search(pattern, data):
            failures.append(label + ': ' + reason)

entries = subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=root).decode().split('\0')
if not any(entries):
    raise SystemExit('No tracked files: stage intended sources before auditing.')
count = 0
for entry in filter(None, entries):
    metadata, relative = entry.split('\t', 1)
    path = root / relative
    if metadata.split()[0] not in {'100644', '100755'} or path.is_symlink():
        failures.append(relative + ': unsupported file mode or symbolic link')
        continue
    if not path.is_file():
        failures.append(relative + ': tracked file missing')
        continue
    check(relative, path.read_bytes(), relative)
    count += 1

# Historical secrets remain exposed even after deletion from the working tree.
head = subprocess.run(['git', 'rev-parse', '--verify', 'HEAD'], cwd=root, capture_output=True)
blobs = 0
if head.returncode == 0:
    objects = subprocess.check_output(['git', 'rev-list', '--objects', '--all'], cwd=root).decode().splitlines()
    for line in objects:
        oid, _, name = line.partition(' ')
        kind = subprocess.check_output(['git', 'cat-file', '-t', oid], cwd=root).strip()
        if kind != b'blob':
            continue
        check(name, subprocess.check_output(['git', 'cat-file', 'blob', oid], cwd=root), 'history ' + oid[:10] + ' ' + name)
        blobs += 1
if failures:
    raise SystemExit('\n'.join(failures))
print(f'Audit passed: {count} tracked files and {blobs} historical blobs. Approved author/contact credits are intentional. Pattern scanning is not proof of absence of every secret.')
