#!/usr/bin/env python3
"""Patch pinned FlClash download-only probe to preserve partial timeout bytes.

This changes no routing, TLS, latency, or regular HTTP probe behavior.
The pinned upstream source must match these anchors exactly or CI fails closed.
"""
from pathlib import Path

file = Path("flclash/core/probe.go")
source = file.read_text(encoding="utf-8")
old_cap = 'if req.maxBody <= 0 || req.maxBody > 5*1024*1024 {'
new_cap = 'if req.maxBody <= 0 || req.maxBody > 16*1024*1024 {'
old_error = """		if copyErr != nil {
			return fail(copyErr)
		}
		return result"""
new_error = """		if copyErr != nil {
			// A bounded download can reach its deadline after transferring
			// useful real bytes. Preserve that body-only sample instead of
			// discarding it; callers still enforce their minimum sample size.
			// Other network errors and probes keep their original semantics.
			if n > 0 && (ctx.Err() == context.DeadlineExceeded ||
				probeErrorKind(copyErr) == probeErrorTimeout) {
				return result
			}
			return fail(copyErr)
		}
		return result"""
for old, new in ((old_cap, new_cap), (old_error, new_error)):
    if source.count(old) != 1:
        raise SystemExit(f"Pinned probe.go changed: expected one match for {old[:40]!r}")
    source = source.replace(old, new, 1)
file.write_text(source, encoding="utf-8")
print("FlClash download-only partial-timeout accounting installed")
