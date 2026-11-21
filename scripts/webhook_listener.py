#!/usr/bin/env python3
"""Minimal webhook receiver used to verify Alertmanager notification delivery.

Appends every POSTed JSON body to /opt/nexora/webhook.log. Binds to all
interfaces on port 5000 so the Alertmanager container can reach it via
host.docker.internal; the EC2 security group does not expose port 5000.
"""

from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_PATH = "/opt/nexora/webhook.log"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(body + "\n---\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 5000), Handler).serve_forever()