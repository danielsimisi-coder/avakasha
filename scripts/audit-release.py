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
        'Keepelix.app/Contents/MacOS/Keepelix',
        'Keepelix.app/Contents/Info.plist',
        'Keepelix.app/Contents/Resources/AppIcon.icns',
        'Keepelix.app/Contents/Resources/LICENSE.txt',
        'Keepelix.app/Contents/Resources/en.lproj/InfoPlist.strings',
        'Keepelix.app/Contents/Resources/he.lproj/InfoPlist.strings',
        'Keepelix.app/Contents/_CodeSignature/CodeResources',
    }
    files = {item.filename for item in archive.infolist() if not item.is_dir()}
    assert files == expected, 'Unexpected or missing packaged files'
    assert archive.testzip() is None, 'Corrupt ZIP'
    for name in files:
        data = archive.read(name)
        assert not re.search(rb'/Users/[A-Za-z0-9_][^/\s]*/', data), 'Machine path in ' + name
        assert not re.search(rb'(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_]{16,}', data), 'Credential pattern in ' + name
    assert archive.read('Keepelix.app/Contents/Resources/LICENSE.txt') == (root/'LICENSE').read_bytes()
    assert archive.read('Keepelix.app/Contents/Resources/AppIcon.icns') == (root/'assets/AppIcon.icns').read_bytes()
    info = plistlib.loads(archive.read('Keepelix.app/Contents/Info.plist'))
    assert info['CFBundleIdentifier'] == 'io.github.danielsimisi-coder.Keepelix'
    assert info['CFBundleLocalizations'] == ['en', 'he'] and info['CFBundleDevelopmentRegion'] == 'en'
    assert 'Daniel Siman Tov' in info['NSHumanReadableCopyright']
print('Release audit passed: exact app payload, matching license/artwork, no detected home paths or credentials.')
