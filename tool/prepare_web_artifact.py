#!/usr/bin/env python3
"""Complete release source maps from the SDK used for this build; never synthesize mappings."""
import argparse
import json
import os
from pathlib import Path
import shutil


def prepare(root: Path, sdk: Path) -> None:
    loader = sdk / 'bin/cache/flutter_web_sdk/flutter_js/flutter.js'
    loader_map = loader.with_suffix('.js.map')
    bootstrap = root / 'flutter_bootstrap.js'
    # The custom template starts with {{flutter_js}}. Offsets remain those of
    # the official loader; a prefix would invalidate its map and must fail.
    if not bootstrap.read_bytes().startswith(loader.read_bytes()):
        raise ValueError('Bootstrap does not begin with the unchanged SDK loader')
    for path in (loader_map, root / 'main.dart.js.map'):
        data = json.loads(path.read_text())
        if data.get('version') != 3 or not data.get('sources') or not data.get('mappings'):
            raise ValueError(f'Missing or invalid source map: {path.name}')
    shutil.copyfile(loader_map, root / 'flutter.js.map')
    print('Verified main.dart.js.map and copied the matching SDK flutter.js.map')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web', default='build/web')
    parser.add_argument('--sdk', default=os.environ.get('FLUTTER_ROOT'))
    args = parser.parse_args()
    sdk = Path(args.sdk) if args.sdk else Path(shutil.which('flutter') or 'flutter').resolve().parent.parent
    prepare(Path(args.web), sdk)
