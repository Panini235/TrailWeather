#!/usr/bin/env python3
"""Check an existing synthetic file's Android VIEW/SEND path on a test package.

The caller supplies a URI readable by the application. This never creates or
removes app data, and only force-stops the named test package for --cold.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--package', required=True)
    parser.add_argument('--uri', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cold', action='store_true')
    parser.add_argument('--send', action='store_true')
    parser.add_argument('--name', default='时间语义回归测试')
    args = parser.parse_args()
    if not args.package.endswith(('.dev', '.qa')):
        parser.error('Only isolated .dev/.qa test packages are supported')
    args.output.mkdir(parents=True, exist_ok=True)

    def adb(*cmd):
        return subprocess.run([args.adb, *cmd], check=True, capture_output=True).stdout

    if args.cold:
        adb('shell', 'am', 'force-stop', args.package)
    intent = ['shell', 'am', 'start', '-n',
              f'{args.package}/dev.trailweather.trailweather.MainActivity',
              '-a', 'android.intent.action.SEND' if args.send else 'android.intent.action.VIEW',
              '-t', 'application/gpx+xml', '--grant-read-uri-permission']
    intent += ['--eu', 'android.intent.extra.STREAM', args.uri] if args.send else ['-d', args.uri]
    adb(*intent)
    time.sleep(2)
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/shanqing-smoke.xml')
    xml = adb('shell', 'cat', '/data/local/tmp/shanqing-smoke.xml')
    (args.output / 'window.xml').write_bytes(xml)
    (args.output / 'screen.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    texts = [n.get('text', '') + n.get('content-desc', '') for n in ET.fromstring(xml).iter('node')]
    text = '\n'.join(texts)
    no_error = 'Page Not Found' not in text and 'GoException' not in text
    confirmation = args.name in text and '导入' in text
    result = {'cold': args.cold, 'action': 'SEND' if args.send else 'VIEW',
              'uri_scheme': args.uri.split(':', 1)[0],
              'no_router_error': no_error, 'import_confirmation': confirmation}
    (args.output / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
    if not (no_error and confirmation):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
