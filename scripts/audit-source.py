#!/usr/bin/env python3
"""Fail closed on common accidental personal payloads in the tracked project."""
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
failures = []
if not any(paths):
    raise SystemExit("No tracked files: stage intended sources before auditing.")
for relative in filter(None, paths):
    path = root / relative
    if not path.is_file():
        continue
    if path.name in {'media.json', 'auth.json', '.env'} or path.suffix in {'.sqlite', '.db', '.p12', '.pem'}:
        failures.append(relative + ': private payload type')
    if path.suffix.lower() in {'.png', '.icns'}:
        continue  # committed artwork must be synthetic; inspect it during review
    data = path.read_bytes()
    if b'\x00' in data:
        failures.append(relative + ': unexpected binary')
        continue
    text = data.decode('utf-8', errors='replace')
    if re.search(r'/Users/[A-Za-z][^/\s]*/', text):
        failures.append(relative + ': machine-specific home path')
    if re.search(r'(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_]{16,}', text):
        failures.append(relative + ': possible credential')
if failures:
    raise SystemExit('\n'.join(failures))
print('Tracked-source audit passed. No personal inventories, home paths or detected credentials.')
