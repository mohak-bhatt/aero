"""Local-only fixtures for retry, owner-tab closure, and cancellation checks."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/slow'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="aero-slow-test.txt"')
            self.send_header('Content-Length', str(1024 * 40))
            self.end_headers()
            try:
                for _ in range(40):
                    self.wfile.write(b'A' * 1024)
                    self.wfile.flush()
                    time.sleep(0.5)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            body = b'<title>Aero Recovery PASS</title><h1>Recovery succeeded</h1><a href="/slow">Slow download</a>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

ThreadingHTTPServer(('127.0.0.1', 18765), Handler).serve_forever()
