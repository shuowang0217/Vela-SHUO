#!/usr/bin/env python3
"""Windows CI: test real FlClash Go RPC binary without internet credentials."""
import json
import os
import hmac
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import socket
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
proxy-groups:
  - name: VELA_SELECT
    type: select
    proxies:
      - Example SS
rules:
  - MATCH,VELA_SELECT
"""
        res = call("velaLoadProfile", {"content": yaml})
        assert "Example SS" in res["proxies"], "Node missing from actual Mihomo"
        assert "GLOBAL" in res["groups"], "Built-in GLOBAL mode is missing"
        config = call("getConfig", os.path.join(home, "config.yaml"))
        assert config["mode"] == "global", "Vela selection must control traffic route"
        actual = call("getProxies")
        assert "Example SS" in actual["proxies"], "FlClash core not populated"
        assert call("changeProxy", {
            "group-name": "GLOBAL", "proxy-name": "Example SS"
        })["message"] == ""
        actual = call("getProxies")
        assert actual["proxies"]["GLOBAL"]["now"] == "Example SS", (
            "Mihomo did not route GLOBAL mode through the selected node")

        # Actual RPC latency verification with a deterministic local 204
        # endpoint. No public network / credential is needed for this test.
        class Local204(BaseHTTPRequestHandler):
            def do_GET(self):
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
                "names": ["DIRECT", "DIRECT", "NOT_CONFIGURED"],
                "test-url": url_204,
            }, timeout=45)
            assert isinstance(batch, list) and len(batch) == 3
            assert [row["name"] for row in batch] == [
                "DIRECT", "DIRECT", "NOT_CONFIGURED",
            ]
            assert batch[0]["value"] > 0 and batch[1]["value"] > 0
            assert batch[2]["value"] == -1
            assert batch[2]["reason"] == "missing"
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
        conn.close()
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
