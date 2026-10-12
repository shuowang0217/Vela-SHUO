#!/usr/bin/env python3
"""Windows CI: test real FlClash Go RPC binary without internet credentials."""
import json
import os
from pathlib import Path
import queue
import struct
import subprocess
import sys
import tempfile
import threading

binary = Path(sys.argv[1]).resolve()
if not binary.is_file():
    raise SystemExit("FlClash Go Core executable missing")
data = queue.Queue()
with tempfile.TemporaryDirectory(prefix="vela-flclash-core-") as home:
    proc = subprocess.Popen([str(binary), "--vela-stdio"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def read_messages():
        try:
            while True:
                head = proc.stdout.read(4)
                if len(head) != 4:
                    return
                size = struct.unpack("<I", head)[0]
                if size == 0 or size > 16*1024*1024:
                    raise RuntimeError("Invalid FlClash RPC frame")
                message = proc.stdout.read(size)
                if len(message) != size:
                    return
                body = json.loads(message)
                if "id" in body:
                    data.put(body)
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
        assert proc.stdin
        proc.stdin.write(struct.pack("<I", len(msg)) + msg)
        proc.stdin.flush()
        while True:
            response = data.get(timeout=timeout)
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
        assert "VELA_SELECT" in res["groups"], "Selector not applied in FlClash"
        actual = call("getProxies")
        assert "Example SS" in actual["proxies"], "FlClash core not populated"
        assert call("changeProxy", {
            "group-name": "VELA_SELECT", "proxy-name": "Example SS"
        })["message"] == ""
        assert call("stopListener") is True
        print("PASS: FlClash GO config parser, selector, nodes and RPC IPC")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
