#!/usr/bin/env python3
"""Windows CI: test real FlClash Go RPC binary without internet credentials."""
import json
import os
import hmac
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import socket
import select
import socketserver
from pathlib import Path
import queue
import struct
import subprocess
import sys
import tempfile
import threading
from collections import deque

binary = Path(sys.argv[1]).resolve()
if not binary.is_file():
    raise SystemExit("FlClash Go Core executable missing")
data = queue.Queue()
diagnostics = deque(maxlen=80)
with tempfile.TemporaryDirectory(prefix="vela-flclash-core-") as home:
    # FlClash's original 4-byte little-endian frames travel through this
    # private TCP socket. Console logs can never corrupt the RPC stream.
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(15)
    token = os.urandom(32)
    endpoint = "127.0.0.1:%d" % listener.getsockname()[1]
    proc = subprocess.Popen(
        [str(binary), "--vela-loopback=%s@%s" % (token.hex(), endpoint)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    conn, remote = listener.accept()
    listener.close()
    conn.settimeout(15)

    def recv_exact(size):
        result = bytearray()
        while len(result) < size:
            block = conn.recv(size - len(result))
            if not block:
                raise EOFError("FlClash RPC stream closed")
            result.extend(block)
        return bytes(result)

    if not hmac.compare_digest(recv_exact(32), token):
        conn.close()
        proc.kill()
        raise RuntimeError("FlClash RPC authentication failed")
    conn.settimeout(None)

    stderr_done = threading.Event()
    def capture_diagnostics():
        # CI uses a synthetic example profile, never a customer's subscription.
        # Keep only a bounded redacted tail and print it ONLY upon failure.
        for raw in iter(proc.stderr.readline, b""):
            line = raw.decode("utf-8", errors="replace").strip()
            line = line.replace("abc123", "[TEST_SECRET]")
            line = line.replace("proxy.example.test", "[TEST_HOST]")
            diagnostics.append(line)
        stderr_done.set()
    threading.Thread(target=capture_diagnostics, daemon=True).start()

    def read_messages():
        try:
            while True:
                head = recv_exact(4)
                size = struct.unpack("<I", head)[0]
                if size == 0 or size > 16*1024*1024:
                    raise RuntimeError("Invalid FlClash RPC frame")
                message = recv_exact(size)
                body = json.loads(message)
                if "id" in body:
                    data.put(body)
        except Exception as exc:
            data.put({"transport_error": type(exc).__name__})
        finally:
            data.put({"transport_dead": True})
    threading.Thread(target=read_messages, daemon=True).start()

    seq = 0
    def call(method, arguments=None, timeout=120):
        global seq
        seq += 1
        key = str(seq)
        msg = json.dumps({"id": key, "method": method,
                          "arguments": arguments}).encode()
        conn.sendall(struct.pack("<I", len(msg)) + msg)
        while True:
            response = data.get(timeout=timeout)
            if response.get("transport_error"):
                raise RuntimeError("FlClash RPC reader: " + response["transport_error"])
            if response.get("transport_dead"):
                raise RuntimeError("FlClash core closed before RPC reply")
            if response.get("id") != key:
                raise RuntimeError("Unexpected FlClash response id")
            if response.get("error"):
                raise RuntimeError(
                    "FlClash rejected %s with %s" %
                    (method, response["error"].get("code")))
            return response.get("result")

    # A synthetic SOCKS5 exit tests an actual Mihomo proxy adapter, not
    # just the built-in DIRECT route. It only forwards to the local CI 204
    # fixture; no third-party network or user subscription is involved.
    class LocalSocks5(socketserver.BaseRequestHandler):
        def handle(self):
            peer = self.request
            peer.settimeout(8)

            def read_exact(count):
                data = b""
                while len(data) < count:
                    chunk = peer.recv(count - len(data))
                    if not chunk:
                        raise EOFError("synthetic SOCKS connection closed")
                    data += chunk
                return data

            try:
                version, methods = read_exact(2)
                if version != 5:
                    return
                read_exact(methods)
                peer.sendall(b"\x05\x00")
                version, cmd, _, family = read_exact(4)
                if version != 5 or cmd != 1:
                    return
                if family == 1:
                    address = socket.inet_ntoa(read_exact(4))
                elif family == 3:
                    count = read_exact(1)[0]
                    address = read_exact(count).decode("ascii")
                elif family == 4:
                    address = socket.inet_ntop(socket.AF_INET6, read_exact(16))
                else:
                    return
                port = struct.unpack("!H", read_exact(2))[0]
                if address not in ("127.0.0.1", "localhost", "::1"):
                    return
                with socket.create_connection((address, port), timeout=5) as dest:
                    dest.settimeout(8)
                    peer.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")
                    while True:
                        ready, _, _ = select.select([peer, dest], [], [], 8)
                        if not ready:
                            return
                        for current in ready:
                            payload = current.recv(16384)
                            if not payload:
                                return
                            (dest if current is peer else peer).sendall(payload)
            except (OSError, EOFError):
                return

    socks_server = socketserver.ThreadingTCPServer(
        ("127.0.0.1", 0), LocalSocks5)
    socks_server.daemon_threads = True
    threading.Thread(target=socks_server.serve_forever, daemon=True).start()

    try:
        assert call("initClash", {"home-dir": home, "version": 0}) is True
        yaml = """
proxies:
  - name: Example SS
    type: ss
    server: proxy.example.test
    port: 443
    cipher: aes-128-gcm
    password: abc123
  - name: Local Socks Test
    type: socks5
    server: 127.0.0.1
    port: SOCKS_LISTEN_PORT
proxy-groups:
  - name: VELA_SELECT
    type: select
    proxies:
      - Example SS
      - Local Socks Test
rules:
  - MATCH,VELA_SELECT
"""
        yaml = yaml.replace(
            "SOCKS_LISTEN_PORT", str(socks_server.server_address[1]))
        res = call("velaLoadProfile", {"content": yaml})
        assert "Local Socks Test" in res["proxies"]
        assert "Example SS" in res["proxies"], "Node missing from actual Mihomo"
        assert "GLOBAL" in res["groups"], "Built-in GLOBAL mode is missing"
        assert res["match-group"] == "VELA_SELECT", (
            "Expose the native MATCH strategy without rewriting routes")
        config = call("getConfig", os.path.join(home, "config.yaml"))
        assert config["mode"] == "rule", "FlClash default RULE must not be replaced"
        # Mode changes are FlClash's native updateConfig RPC, not rewrites
        # of subscription YAML. Test the exact GLOBAL selection behavior.
        assert call("updateConfig", {"mode": "global"}) == ""
        actual = call("getProxies")
        assert "Example SS" in actual["proxies"], "FlClash core not populated"
        assert call("changeProxy", {
            "group-name": "GLOBAL", "proxy-name": "Example SS"
        })["message"] == ""
        actual = call("getProxies")
        assert actual["proxies"]["GLOBAL"]["now"] == "Example SS", (
            "Mihomo did not route GLOBAL mode through the selected node")
        assert call("changeProxy", {
            "group-name": "VELA_SELECT", "proxy-name": "Local Socks Test"
        })["message"] == ""
        assert call("updateConfig", {"mode": "rule"}) == ""
        actual = call("getProxies")
        assert actual["proxies"]["GLOBAL"]["now"] == "Example SS"
        assert actual["proxies"]["VELA_SELECT"]["now"] == "Local Socks Test", (
            "RULE policy group must be independent of GLOBAL")

        # Actual RPC latency verification with a deterministic local 204
        # endpoint. No public network / credential is needed for this test.
        class Local204(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path in ("/download", "/download-short", "/download-truncated"):
                    size = 1048576 if self.path == "/download" else 320 * 1024
                    # A correctly sized smaller body is a valid sample.
                    # A truncated response must fail safely, as in the
                    # FlClash-Custom io.Copy error-checking code.
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Length", str(1048576 if self.path != "/download-short" else size))
                    self.end_headers()
                    payload = bytes(range(256)) * 256
                    for _ in range((size + len(payload) - 1) // len(payload)):
                        self.wfile.write(payload[:min(len(payload), size)])
                        size -= min(len(payload), size)
                        time.sleep(.005)
                    return
                time.sleep(.045)  # ensure nonzero delay even on fast CI
                self.send_response(204)
                self.end_headers()

            def log_message(self, fmt, *args):
                pass

        endpoint_204 = ThreadingHTTPServer(("127.0.0.1", 0), Local204)
        threading.Thread(target=endpoint_204.serve_forever, daemon=True).start()
        try:
            url_204 = "http://127.0.0.1:%d/generate_204" % (
                endpoint_204.server_port)
            # DIRECT is a built-in Mihomo outbound, not the unreachable
            # example SS; this checks the REAL Go URLTest RPC execution.
            delay = call("asyncTestDelay", {
                "proxy-name": "DIRECT", "test-url": url_204,
                "timeout": 8000,
            }, timeout=30)
            assert isinstance(delay, dict), "FlClash delay RPC returned no object"
            assert delay["name"] == "DIRECT"
            assert delay["value"] > 0, (
                "Original Mihomo URLTest could not access local HTTP 204")
            result = call("probe", {
                "url": url_204, "proxy-name": "DIRECT",
                "timeout": 8000, "max-body": 0, "headers": {},
            }, timeout=30)
            assert result["status-code"] == 204
            assert result["delay"] > 0
            assert not result.get("error")

            # This is the SAME one-RPC batch used by the Vela proxy page.
            # Check two legitimate measurements and one missing node without
            # requiring a public proxy or leaking real subscription tokens.
            batch = call("velaTestLatencies", {
                "names": ["DIRECT", "Local Socks Test", "NOT_CONFIGURED"],
                "test-url": url_204,
            }, timeout=45)
            assert isinstance(batch, list) and len(batch) == 3
            assert [row["name"] for row in batch] == [
                "DIRECT", "Local Socks Test", "NOT_CONFIGURED",
            ]
            assert batch[0]["value"] > 0, "FlClash DIRECT latency failed"
            assert batch[1]["value"] > 0, (
                "Real Mihomo SOCKS5 proxy outbound latency failed")
            assert batch[2]["value"] == -1
            assert batch[2]["reason"] == "missing"

            # Download MUST traverse FlClash's selected SOCKS5 adapter,
            # use streaming bytes instead of binary JSON, and work without
            # an active browser-facing mixed-port listener.
            for suffix, minimum, maximum in (
                ("/download", 1048576, 1048576),
                ("/download-short", 320 * 1024, 320 * 1024),
            ):
                sample = call("velaTestDownload", {
                    "proxy-name": "Local Socks Test",
                    "test-url": "http://127.0.0.1:%d%s" %
                                (endpoint_204.server_port, suffix),
                }, timeout=35)
                assert sample["ok"] is True, "Native FlClash download failed"
                assert minimum <= sample["bytes"] <= maximum
                assert sample["mbps"] > 0, "Sample throughput was not measured"
            truncated = call("velaTestDownload", {
                "proxy-name": "Local Socks Test",
                "test-url": "http://127.0.0.1:%d/download-truncated" %
                            endpoint_204.server_port,
            }, timeout=35)
            assert truncated["ok"] is False, (
                "FlClash-Custom must reject incomplete HTTP body transfers")
            missing = call("velaTestDownload", {
                "proxy-name": "NOT_CONFIGURED",
                "test-url": "http://127.0.0.1:%d/download" %
                            endpoint_204.server_port,
            }, timeout=35)
            assert missing == {"ok": False, "reason": "missing"}
        finally:
            endpoint_204.shutdown()
            endpoint_204.server_close()

        assert call("startListener") is True
        # startListener returning true is not sufficient: prove the actual
        # FlClash/Mihomo MixedPort is accepting local proxy connections.
        with socket.create_connection(("127.0.0.1", 20808), timeout=5) as mixed:
            assert mixed.getpeername()[1] == 20808
        assert call("stopListener") is True
        print("PASS: FlClash GO config parser, selector, nodes and RPC IPC")
    except Exception:
        # The Go stderr reader races with the RPC EOF reader; allow native
        # panic/fatal output to drain before showing the diagnostic tail.
        try:
            exit_code = proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            exit_code = "still-running"
        stderr_done.wait(timeout=2)
        print("FlClash Go exited=%s" % exit_code, file=sys.stderr)
        print("FlClash synthetic profile diagnostic tail:", file=sys.stderr)
        for line in list(diagnostics)[-50:]:
            print(line[:500], file=sys.stderr)
        raise
    finally:
        socks_server.shutdown()
        socks_server.server_close()
        conn.close()
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
