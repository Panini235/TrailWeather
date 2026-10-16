#!/usr/bin/env python3
"""Preview a CI Web artifact on loopback with HTTP gzip content negotiation.

Usage: python3 tool/serve_web.py /path/to/web-release --port 8766
No Flutter build, source rewriting, external proxy or public deployment occurs.
"""
import argparse
from functools import lru_cache, partial
import gzip
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import Path


@lru_cache(maxsize=16)
def compressed_file(path, modified_ns, size):
    data = gzip.compress(Path(path).read_bytes(), compresslevel=6, mtime=0)
    return data, '"' + hashlib.sha256(data).hexdigest() + '"'


def accepts_gzip(value):
    for item in value.lower().split(','):
        parts = [p.strip() for p in item.split(';')]
        if parts[0] != 'gzip':
            continue
        for parameter in parts[1:]:
            if parameter.startswith('q='):
                try:
                    return float(parameter[2:]) > 0
                except ValueError:
                    return False
        return True
    return False


class PreviewHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm'}

    def end_headers(self):
        self.send_header('Vary', 'Accept-Encoding')
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def send_head(self):
        path = Path(self.translate_path(self.path))
        if path.is_dir():
            path = path / 'index.html'
        if (not accepts_gzip(self.headers.get('Accept-Encoding', ''))
                or not path.is_file()
                or path.suffix not in {'.html', '.js', '.wasm', '.css', '.json', '.svg'}):
            return super().send_head()
        # The bundled application is below this limit; unknown large files stream normally.
        stat = path.stat()
        if stat.st_size > 32 * 1024 * 1024:
            return super().send_head()
        body, etag = compressed_file(str(path), stat.st_mtime_ns, stat.st_size)
        unchanged = self.headers.get('If-None-Match') == etag
        self.send_response(304 if unchanged else 200)
        self.send_header('ETag', etag)
        # Unhashed filenames must revalidate on a new build; never pin stale application code.
        if not unchanged:
            self.send_header('Content-Type', self.guess_type(str(path)))
            self.send_header('Content-Encoding', 'gzip')
            self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        return None if unchanged else BytesIO(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--port', type=int, default=8766)
    args = parser.parse_args()
    root = args.directory.resolve()
    if not (root / 'index.html').is_file():
        parser.error('Select a downloaded CI web-release directory containing index.html')
    handler = partial(PreviewHandler, directory=str(root))
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler)
    print(f'Previewing {root} at http://127.0.0.1:{args.port}/ (gzip enabled)', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
