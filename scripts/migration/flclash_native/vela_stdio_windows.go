//go:build windows && !(android && cgo)

package main

import (
    "os"
    "time"
)

// Vela is the graphical host; this transport only carries the ORIGINAL
// FlClash CoreMethod JSON frames, not a second network implementation.
// The existing FlClash server.go handles framing, concurrency and RPC dispatch.
type velaStdioConn struct{}

func (*velaStdioConn) Read(p []byte) (int, error) { return os.Stdin.Read(p) }
func (*velaStdioConn) Write(p []byte) (int, error) { return os.Stdout.Write(p) }
func (*velaStdioConn) Close() error { return nil }
func (*velaStdioConn) SetWriteDeadline(_ time.Time) error { return nil }
