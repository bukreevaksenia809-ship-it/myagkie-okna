#!/usr/bin/env python3
"""Простой веб-сервер для демонстрации: отдаёт build/web со сжатием gzip.

Запуск:
    cd soft_window_drawer
    python3 serve_web.py 8080

Зачем свой сервер: `python3 -m http.server` не сжимает ответы, а собранный
Flutter-бандл весит ~3,5 МБ — через туннель это грузится очень долго.
Здесь .js/.json/.html/.css/.wasm/.svg отдаются gzip-ом (~1 МБ).
"""
import gzip
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')
COMPRESSIBLE = ('.js', '.json', '.html', '.css', '.wasm', '.svg', '.bin')


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        # Flutter web требует корректных MIME для .wasm и .js
        path = self.path.split('?')[0]
        if path.endswith('.wasm'):
            self.send_header('Content-Type', 'application/wasm')
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            path = os.path.join(path, 'index.html')
        if not os.path.isfile(path):
            # SPA: неизвестные пути отдаём как index.html
            path = os.path.join(ROOT, 'index.html')
        if not path.endswith(COMPRESSIBLE):
            return super().send_head()

        try:
            with open(path, 'rb') as handle:
                body = handle.read()
        except OSError:
            return super().send_head()

        if 'gzip' not in self.headers.get('Accept-Encoding', ''):
            return super().send_head()

        payload = gzip.compress(body, compresslevel=6)
        self.send_response(200)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Encoding', 'gzip')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        return _BytesReader(payload)


class _BytesReader:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def read(self, size=-1):
        if size is None or size < 0:
            chunk = self.data[self.pos:]
            self.pos = len(self.data)
            return chunk
        chunk = self.data[self.pos:self.pos + size]
        self.pos += len(chunk)
        return chunk

    def close(self):
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    if not os.path.isdir(ROOT):
        sys.exit('Нет папки build/web — сначала выполните: flutter build web --release')
    print(f'Раздаю {ROOT} на http://0.0.0.0:{port} (gzip включён)')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
