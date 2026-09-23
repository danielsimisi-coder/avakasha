#!/usr/bin/env python3
"""Audit tracked source and every reachable Git blob; report locations, never secret values."""
import hashlib
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
# Every reviewed synthetic version of each image, so historical blobs stay verifiable.
artwork = {
    'assets/avakasha-preview.png': {'de27146eec2287094fd61eda87be6806c34399f2c6c98250e85370486f0882fc', '454c6a7863bbfd437fa25622076727b5c62fbf76c657eb870fb0aeedc21083e8', 'dea62e645ac86262c9b5bbfd54d384ac4fe215e34f191b8c16590cd03b968282'},
    'assets/avakasha-older-files.png': {'4e51d5dfa9610f64fdbd84e1df64132fe943768897bf53fb57ef5245f505e2f4', '6472fdc44bccb5f9cd49cec3e641144180d89904d81770854bdbab8431f6dfd3', 'cce8db24fdb3e338d4b35f0c0ec5dd741ec66a9adb6aee29ac0d178ce0750e87', 'ecc040001e557ed66f7aee88c6033fb71cebdd7a3987d946b8d0844c2c90f3bb'},
    'assets/avakasha-storage-map.png': {'1260c7ae83e01b4d35b12c5bae6e621067b6d294efbc65078281231e3a6e83e3', '8dc819fc57b5a02dfd334e4e4818c4d453a9503a0d157c6dea953d361eb2a856'},
    'assets/avakasha-hebrew.png': {'35d47605559f3408daf487d12b490cbc8e4b0d4ad226456528891ec449591659', 'e9766f7357233717c57c69a0d082114cfc27376d37bd0e2fd6030b852cfec6be'},
    'assets/avakasha-video.png': {'42245c97681e81e00d511b253f803c4471bd5739115b8d6619965edd8ae52bb7', '6b0586209ecdf067953df8847615c4480b3943d2899106f3bd631955ab5e284e'},
    'assets/keepelix-preview.png': {'de27146eec2287094fd61eda87be6806c34399f2c6c98250e85370486f0882fc', '454c6a7863bbfd437fa25622076727b5c62fbf76c657eb870fb0aeedc21083e8'},
    'assets/keepelix-older-files.png': {'4e51d5dfa9610f64fdbd84e1df64132fe943768897bf53fb57ef5245f505e2f4', '6472fdc44bccb5f9cd49cec3e641144180d89904d81770854bdbab8431f6dfd3'},
    'assets/keepelix-storage-map.png': {'1260c7ae83e01b4d35b12c5bae6e621067b6d294efbc65078281231e3a6e83e3'},
    'assets/keepelix-hebrew.png': {'35d47605559f3408daf487d12b490cbc8e4b0d4ad226456528891ec449591659'},
    'assets/keepelix-video.png': {'42245c97681e81e00d511b253f803c4471bd5739115b8d6619965edd8ae52bb7'},
    'assets/avakasha-overview.png': {'e4bd01bce6cd5156521ffc8058a044a2165ee49e6d3fe4c8f43d1b6805bf07d1'},
    'assets/icon-1024.png': {'95ff2ed3079abdc2143948ec1586c53a19fbdeb30ecbefa06d37c99f2129531b', '019380b7d4997cc8c8f83ea40672fac25bdd2a4f10c6f69fcb7eaa9c75132db7'},
    'assets/AppIcon.icns': {'9f603b3652db574dae84fa3b67f738a1455618a58590204bdee54be5f574dc97', '876a9099c5e0b7aec0a93ea8c2b68adc394d9accaaf2cfb2862ac749a50df7be'},
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
        if hashlib.sha256(data).hexdigest() not in artwork[relative]:
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
