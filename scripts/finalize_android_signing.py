#!/usr/bin/env python3
"""Finalize Android release signing with the existing permanent SHUO key.

This program deliberately DOES NOT generate a new certificate. It applies the
known key, verifies the APK cryptographically, compares its public fingerprint,
and atomically replaces the distributable only after verification.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

EXPECTED_SHA256 = "3e8826e8aa48576ddfce7a9a2e78106a159c7be05dbb3b2f89eb60fb095ac9d9"
HEX_DIGEST = re.compile(r"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}:){31}[0-9a-f]{2}(?![0-9a-f])|(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])")


def extract_certificate_sha256(output: str) -> set[str]:
    """Accept apksigner variants, with or without colons/leading whitespace."""
    found: set[str] = set()
    for line in output.splitlines():
        # Ignore v1/v2 content SHA and all unrelated 64-hex data.
        normalized_label = line.casefold().replace(" ", "")
        if "certificate" not in normalized_label or "sha-256" not in normalized_label:
            continue
        if "digest" not in normalized_label and "fingerprint" not in normalized_label:
            continue
        # Look only after SHA-256's label; do not confuse other hashes.
        label_match = re.search(r"(?i)sha[\s-]*256\s*(?:digest|fingerprint)\s*[:=]", line)
        if label_match is None:
            continue
        for match in HEX_DIGEST.finditer(line[label_match.end():]):
            found.add(match.group(0).replace(":", "").lower())
    return found


def finalize(apk: Path, keystore: Path, signer: Path) -> None:
    if not apk.is_file() or not keystore.is_file() or not signer.is_file():
        raise RuntimeError("Release APK, restored keystore or Android apksigner missing")
    if not os.environ.get("SHUO_SIGNING_PASSWORD"):
        raise RuntimeError("Permanent SHUO signing secret is unavailable")

    # Sign every time rather than try to infer whether Flutter used a debug
    # signing config. The input APK is already zipaligned by Flutter.
    temp = apk.with_name(apk.stem + ".permanently-signed.apk")
    temp.unlink(missing_ok=True)
    try:
        subprocess.run(
            [str(signer), "sign",
             "--ks", str(keystore), "--ks-key-alias", "shuo-release",
             "--ks-pass", "env:SHUO_SIGNING_PASSWORD",
             "--key-pass", "env:SHUO_SIGNING_PASSWORD",
             "--out", str(temp), str(apk)],
            check=True, capture_output=True, text=True,
        )

        result = subprocess.run(
            [str(signer), "verify", "--verbose", "--print-certs", str(temp)],
            check=True, capture_output=True, text=True,
        )
        fingerprints = extract_certificate_sha256(result.stdout + "\n" + result.stderr)
        if fingerprints != {EXPECTED_SHA256}:
            # These are public digest strings, not passwords or private keys.
            raise RuntimeError(
                "APK certificate fingerprint mismatch or unrecognized output "
                f"(observed certificates: {', '.join(sorted(fingerprints)) or 'none'})"
            )
        # Ensure the published APK is the verified, permanently signed one.
        temp.replace(apk)
        print(f"Android APK verified with permanent SHUO signing certificate: {EXPECTED_SHA256}")
    finally:
        temp.unlink(missing_ok=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--apk", type=Path, required=True)
    p.add_argument("--keystore", type=Path, required=True)
    p.add_argument("--apksigner", type=Path, required=True)
    args = p.parse_args()
    try:
        finalize(args.apk, args.keystore, args.apksigner)
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        # Do not print captured tool stderr: some Java tools may echo args.
        print(f"Vela permanent APK signing failed: {type(exc).__name__}: "
              f"{exc if isinstance(exc, RuntimeError) else 'native sign/verify error'}",
              file=sys.stderr)
        sys.exit(1)
