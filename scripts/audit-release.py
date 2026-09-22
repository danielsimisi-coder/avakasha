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
        'Avakasha.app/Contents/MacOS/Avakasha',
        'Avakasha.app/Contents/Info.plist',
        'Avakasha.app/Contents/Resources/AppIcon.icns',
        'Avakasha.app/Contents/Resources/LICENSE.txt',
        'Avakasha.app/Contents/Resources/en.lproj/InfoPlist.strings',
        'Avakasha.app/Contents/Resources/he.lproj/InfoPlist.strings',
        'Avakasha.app/Contents/_CodeSignature/CodeResources',
    }
    files = {item.filename for item in archive.infolist() if not item.is_dir()}
    assert files == expected, 'Unexpected or missing packaged files'
    assert archive.testzip() is None, 'Corrupt ZIP'
    for name in files:
        data = archive.read(name)
        assert not re.search(rb'/Users/[A-Za-z0-9_][^/\s]*/', data), 'Machine path in ' + name
        assert not re.search(rb'(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_]{16,}', data), 'Credential pattern in ' + name
    assert archive.read('Avakasha.app/Contents/Resources/LICENSE.txt') == (root/'LICENSE').read_bytes()
    assert archive.read('Avakasha.app/Contents/Resources/AppIcon.icns') == (root/'assets/AppIcon.icns').read_bytes()
    info = plistlib.loads(archive.read('Avakasha.app/Contents/Info.plist'))
    assert info['CFBundleIdentifier'] == 'io.github.danielsimisi-coder.Avakasha'
    assert info['CFBundleLocalizations'] == ['en', 'he'] and info['CFBundleDevelopmentRegion'] == 'en'
    assert 'Daniel Siman Tov' in info['NSHumanReadableCopyright']
print('Release audit passed: exact app payload, matching license/artwork, no detected home paths or credentials.')
