#!/usr/bin/env python3
"""Local, deterministic browsing and download fixtures. Binds only to loopback."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/disconnect':
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            return
        if self.path == '/download':
            body = b'NotchBrow download verified.\n'
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="notchbrow-test.txt"')
        else:
            body = b'''<!doctype html><html><head><title>NotchBrow fixture</title></head>
            <body><h1>A page inside the notch</h1>
            <a id="newtab" href="/second" target="_blank">Open another tab</a>
            <a id="download" href="/download" download>Download a file</a>
            <input id="editable" aria-label="Editable test field" value="Native WebKit"></body></html>'''
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_address[1]))
server.serve_forever()
