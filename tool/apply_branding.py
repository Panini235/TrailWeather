#!/usr/bin/env python3
"""Apply committed icons after flutter create; uses only Python's standard library."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import struct
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
BRAND = REPO / 'assets/branding'
NAME = json.loads((BRAND / 'selection.json').read_text())['displayName']
ANDROID = '{http://schemas.android.com/apk/res/android}'


def png_size(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[25] != 2:
        raise ValueError(f'Expected opaque RGB PNG: {path}')
    return struct.unpack('>II', data[16:24])


def verify_sources():
    assert png_size(BRAND / 'app-icon.png') == (1024, 1024)
    catalog = BRAND / 'platforms/ios/AppIcon.appiconset'
    for image in json.loads((catalog / 'Contents.json').read_text())['images']:
        size = int(float(image['size'].split('x')[0]) * int(image['scale'][:-1]))
        assert png_size(catalog / image['filename']) == (size, size)
    for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        assert png_size(BRAND / f'platforms/android/mipmap-{density}/ic_launcher.png') == (size, size)
    for source in (BRAND / 'platforms/android').rglob('*.xml'):
        ET.parse(source)


def apply(platform, project, check_only):
    source = BRAND / 'platforms' / platform
    target = project / {
        'android': 'android/app/src/main/res',
        'ios': 'ios/Runner/Assets.xcassets',
        'web': 'web',
    }[platform]
    if not (project / platform).is_dir():
        raise ValueError(f'Run flutter create for {platform} before applying branding')
    files = [p for p in source.rglob('*') if p.is_file()]
    if not files:
        raise ValueError(f'No source icons for {platform}')
    for original in files:
        destination = target / original.relative_to(source)
        if not check_only:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, destination)
        if not destination.is_file() or original.read_bytes() != destination.read_bytes():
            raise ValueError(f'Brand icon missing or overwritten: {destination}')
    if platform == 'android':
        application = ET.parse(project / 'android/app/src/main/AndroidManifest.xml').find('application')
        assert application.get(ANDROID + 'label') == NAME
        assert application.get(ANDROID + 'icon') == '@mipmap/ic_launcher'
    elif platform == 'ios':
        info = plistlib.loads((project / 'ios/Runner/Info.plist').read_bytes())
        assert info['CFBundleDisplayName'] == info['CFBundleName'] == NAME
    else:
        manifest = json.loads((project / 'web/manifest.json').read_text())
        assert manifest['name'] == manifest['short_name'] == NAME
        assert f'<title>{NAME}｜徒步天气与行前规划</title>' in (project / 'web/index.html').read_text()
        for image in manifest['icons']:
            assert png_size(project / 'web' / image['src']) == tuple(map(int, image['sizes'].split('x')))
    print(f'{platform}: {NAME}, {len(files)} brand assets verified')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platforms', choices=['android', 'ios', 'web'], nargs='+', required=True)
    parser.add_argument('--project-root', type=Path, default=REPO)
    parser.add_argument('--check', action='store_true', help='Validate without writing platform files')
    args = parser.parse_args()
    verify_sources()
    for platform in args.platforms:
        apply(platform, args.project_root.resolve(), args.check)


if __name__ == '__main__':
    main()
