#!/usr/bin/env python3
"""Verify the display name and brand resources in CI build artifacts."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

from configure_release import APP_ID

REPO = Path(__file__).resolve().parents[1]
BRAND = REPO / 'assets/branding'
NAME = json.loads((BRAND / 'selection.json').read_text())['displayName']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--ios-app', type=Path)
    parser.add_argument('--web', type=Path)
    args = parser.parse_args()
    if not any([args.apk, args.ios_app, args.web]):
        parser.error('Select at least one build artifact')
    if args.apk:
        sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
        tools = list((sdk / 'build-tools').glob('*/aapt'))
        if not tools:
            raise RuntimeError('Android build-tools aapt is required')
        aapt = max(tools, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))
        badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(args.apk)], text=True)
        assert f"application-label:'{NAME}'" in badging, 'APK display name mismatch'
        assert 'application-icon-' in badging, 'APK launcher icon missing'
        assert f"package: name='{APP_ID}'" in badging, 'APK applicationId mismatch'
        with zipfile.ZipFile(args.apk) as apk:
            assert apk.read('assets/flutter_assets/assets/branding/app-icon.png') == (BRAND / 'app-icon.png').read_bytes()
        print(f'APK: {APP_ID}, {NAME} display name, launcher declaration and brand image verified')
    if args.ios_app:
        info = plistlib.loads((args.ios_app / 'Info.plist').read_bytes())
        assert info['CFBundleDisplayName'] == info['CFBundleName'] == NAME
        assert info['CFBundleIdentifier'] == APP_ID, 'iOS bundle id mismatch'
        icon = info['CFBundleIcons']['CFBundlePrimaryIcon']
        assert icon['CFBundleIconName'] == 'AppIcon'
        assert icon['CFBundleIconFiles']
        assert (args.ios_app / 'Assets.car').is_file()
        print(f'iOS: {APP_ID}, {NAME} display name and compiled AppIcon catalog verified')
    if args.web:
        manifest = json.loads((args.web / 'manifest.json').read_text())
        assert manifest['name'] == manifest['short_name'] == NAME
        assert f'<title>{NAME}｜徒步天气与行前规划</title>' in (args.web / 'index.html').read_text()
        for source in (BRAND / 'platforms/web').rglob('*.png'):
            assert (args.web / source.relative_to(BRAND / 'platforms/web')).read_bytes() == source.read_bytes()
        print(f'Web: {NAME} title, manifest and icons verified')


if __name__ == '__main__':
    main()
