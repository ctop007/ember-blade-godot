#!/usr/bin/env python3
"""Static server with COOP/COEP headers (needed for Godot Web Thread Support builds).
Usage: python3 tools/serve_coop.py <port> <dir>"""
import functools
import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8942
root = sys.argv[2] if len(sys.argv) > 2 else "build/web-mt"
http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=root)).serve_forever()
