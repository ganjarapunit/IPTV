#!/usr/bin/env python3
"""
Threaded LAN HTTP server for serving an M3U playlist to a TV.

Adds two things over `python -m http.server`:
  * Threading, so the player can fetch the playlist and segments concurrently.
  * HTTP Range support, which ExoPlayer (Tizen) requires for seeking and for
    buffering partial segments.

Usage:  python iptv_server.py [root_dir] [port]
"""

import os
import re
import sys
import time
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
LOG = os.path.join(os.path.dirname(ROOT), "logs", "server.log")


def log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except Exception:
        pass


class RangeHandler(SimpleHTTPRequestHandler):
    server_version = "IPTVPlaylist/1.0"

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def log_message(self, fmt, *args):
        log("%s %s" % (self.address_string(), fmt % args))

    def send_head(self):
        rng = self.headers.get("Range")
        if not rng:
            return SimpleHTTPRequestHandler.send_head(self)

        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return SimpleHTTPRequestHandler.send_head(self)

        try:
            f = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None

        size = os.fstat(f.fileno()).st_size
        m = re.match(r"bytes=(\d*)-(\d*)$", rng.strip())
        if not m:
            f.close()
            return SimpleHTTPRequestHandler.send_head(self)

        start_s, end_s = m.groups()
        if start_s:
            start = int(start_s)
            end = int(end_s) if end_s else size - 1
        else:
            # suffix range: last N bytes
            length = int(end_s or 0)
            start = max(0, size - length)
            end = size - 1

        if start >= size or start > end:
            f.close()
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % size)
            self.end_headers()
            return None

        end = min(end, size - 1)
        length = end - start + 1

        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Last-Modified",
                         self.date_time_string(os.fstat(f.fileno()).st_mtime))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        f.seek(start)
        self.range_remaining = length
        return f

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "range_remaining", None)
        if remaining is None:
            return SimpleHTTPRequestHandler.copyfile(self, source, outputfile)
        while remaining > 0:
            chunk = source.read(min(65536, remaining))
            if not chunk:
                break
            try:
                outputfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                break
            remaining -= len(chunk)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    os.chdir(ROOT)
    log("--- server start on port %d, root=%s ---" % (PORT, ROOT))
    print("Serving %s on http://0.0.0.0:%d  (Ctrl+C to stop)" % (ROOT, PORT))
    print("Logs: %s" % LOG)
    try:
        Server(("0.0.0.0", PORT), RangeHandler).serve_forever()
    except KeyboardInterrupt:
        log("--- server stopped ---")
