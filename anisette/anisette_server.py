"""Run your own Anisette server so every PC on your network shares one machine identity.

Anisette is the machine identity Apple wants alongside a sign-in. Public servers
are shared by everybody and often throttled, so this serves the same endpoints
from your own machine: it fetches a machine identity from an upstream server,
keeps it here, and hands the same headers to every device that asks.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAMS = [
    "https://ani.lillq.me",
    "https://new.ani.sidestore.io",
    "https://mac-ani.jkcoxson.com",
    "https://ani.iloader.app",
    "https://ani.jkcoxson.com",
    "https://ani2.stikstore.app",
]

HEADER_KEYS = [
    "X-Apple-I-MD",
    "X-Apple-I-MD-M",
    "X-Apple-I-MD-RINFO",
    "X-Apple-I-MD-LU",
    "X-Apple-I-SRL-NO",
    "X-Apple-I-Client-Time",
    "X-Apple-I-TimeZone",
    "X-MMe-Client-Info",
    "X-Apple-Locale",
]

CLIENT_INFO = "<MacBookPro13,3> <Mac OS X;10.12.6;16G29> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
USER_AGENT = "akd/1.0 CFNetwork/811.5.4 Darwin/16.7.0"
CACHE_SECONDS = 600


class Cache:
    """One machine identity, refreshed only when it is old or broken."""

    def __init__(self, upstreams):
        self.upstreams = upstreams
        self.lock = threading.Lock()
        self.headers = {}
        self.client_info = {"client_info": CLIENT_INFO, "user_agent": USER_AGENT}
        self.fetched_at = 0.0
        self.upstream = ""

    def stale(self):
        return not self.headers or time.time() - self.fetched_at > CACHE_SECONDS

    def get(self, force=False):
        with self.lock:
            if not force and not self.stale():
                return self.headers, self.client_info
            problems = []
            for upstream in self.upstreams:
                base = upstream.rstrip("/")
                try:
                    headers = json.loads(fetch(base + "/", timeout=20))
                    missing = [key for key in HEADER_KEYS if not headers.get(key)]
                    if missing:
                        raise ValueError("missing " + ", ".join(missing))
                    try:
                        info = json.loads(fetch(base + "/v3/client_info", timeout=10))
                    except Exception:
                        info = {}
                    self.headers = {key: str(value) for key, value in headers.items()}
                    self.client_info = {
                        "client_info": info.get("client_info") or CLIENT_INFO,
                        "user_agent": info.get("user_agent") or USER_AGENT,
                    }
                    self.fetched_at = time.time()
                    self.upstream = base
                    return self.headers, self.client_info
                except Exception as error:
                    problems.append("%s (%s)" % (base, error))
            if self.headers:
                print("refreshing failed, serving the cached identity: %s" % "; ".join(problems))
                return self.headers, self.client_info
            raise RuntimeError("no upstream answered: " + "; ".join(problems))


def fetch(url, timeout=20):
    request = urllib.request.Request(url, headers={"User-Agent": "anisette-server"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def public_ip():
    for url in ("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"):
        try:
            address = fetch(url, timeout=8).strip()
            if address:
                return address
        except Exception:
            continue
    return ""


def local_ip():
    import socket

    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 80))
        return probe.getsockname()[0]
    except Exception:
        return ""
    finally:
        probe.close()


def make_handler(cache):
    class Handler(BaseHTTPRequestHandler):
        server_version = "AnisetteServer"

        def send_json(self, payload, status=200):
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.path.split("?")[0].rstrip("/") or "/"
            force = "refresh=1" in self.path
            if path in ("/", "/v3/get_headers"):
                try:
                    headers, _info = cache.get(force=force)
                except Exception as error:
                    self.send_json({"error": str(error)}, 502)
                    return
                self.send_json(headers)
                return
            if path == "/v3/client_info":
                _headers, info = cache.get()
                self.send_json(info)
                return
            if path == "/health":
                self.send_json({"ok": True, "upstream": cache.upstream})
                return
            if path == "/v3/provision" or path == "/provision":
                self.send_json({"error": "this server reuses one machine identity; nothing to provision"}, 400)
                return
            self.send_json({"error": "unknown path " + path}, 404)

        def do_POST(self):
            self.send_json({"error": "this server reuses one machine identity; nothing to provision"}, 400)

        def log_message(self, fmt, *args):
            print("%s %s" % (self.address_string(), fmt % args))

    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description="Serve Anisette data from your own machine.")
    parser.add_argument("--port", type=int, default=6969)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--upstream", action="append", default=None,
                        help="Anisette server to fetch the identity from (repeatable).")
    parser.add_argument("--no-public-ip", action="store_true", help="Skip the public IP lookup.")
    args = parser.parse_args(argv)

    cache = Cache(args.upstream or UPSTREAMS)
    try:
        cache.get()
    except Exception as error:
        print("Could not reach any upstream Anisette server yet (%s)." % error)
        print("Starting anyway; the first request will retry.")

    server = ThreadingHTTPServer((args.host, args.port), make_handler(cache))
    lan = local_ip()
    print("")
    print("Anisette server running on port %d" % args.port)
    print("  This PC:      http://127.0.0.1:%d" % args.port)
    if lan:
        print("  Your network: http://%s:%d" % (lan, args.port))
    if not args.no_public_ip:
        address = public_ip()
        if address:
            print("  Public:       http://%s:%d" % (address, args.port))
            print("")
            print("Paste that public address into SuperStore's anisette server box.")
            print("If it does not answer from outside, forward TCP %d on your router." % args.port)
        else:
            print("  Public:       could not be looked up; check your network and try again.")
    print("")
    print("Press Ctrl+C to stop.")
    print("")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
