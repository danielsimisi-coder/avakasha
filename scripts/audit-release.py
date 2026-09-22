#!/usr/bin/env python3
"""Inspect the built ZIP without launching it or extracting user-controlled paths."""
import pathlib
import plistlib
import re
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
with zipfile.ZipFile(sys.argv[1]) as archive:
    expected = {
        'FileTriage.app/Contents/MacOS/FileTriage',
        'FileTriage.app/Contents/Info.plist',
        'FileTriage.app/Contents/Resources/AppIcon.icns',
        'FileTriage.app/Contents/Resources/LICENSE.txt',
        'FileTriage.app/Contents/_CodeSignature/CodeResources',
    }
    files = {item.filename for item in archive.infolist() if not item.is_dir()}
    assert files == expected, 'Unexpected or missing packaged files'
    assert archive.testzip() is None, 'Corrupt ZIP'
    for name in files:
        data = archive.read(name)
        assert not re.search(rb'/Users/[A-Za-z0-9_][^/\s]*/', data), 'Machine path in ' + name
        assert not re.search(rb'(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_]{16,}', data), 'Credential pattern in ' + name
    assert archive.read('FileTriage.app/Contents/Resources/LICENSE.txt') == (root/'LICENSE').read_bytes()
    assert archive.read('FileTriage.app/Contents/Resources/AppIcon.icns') == (root/'assets/AppIcon.icns').read_bytes()
    info = plistlib.loads(archive.read('FileTriage.app/Contents/Info.plist'))
    assert info['CFBundleIdentifier'] == 'io.github.danielsimisi-coder.FileTriage'
    assert 'Daniel Siman Tov' in info['NSHumanReadableCopyright']
print('Release audit passed: exact app payload, matching license/artwork, no detected home paths or credentials.')
