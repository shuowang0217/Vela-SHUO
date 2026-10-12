//go:build windows && !(android && cgo)

package main

import (
    "io"
    "os"
    "time"
)

// Go's Mihomo configuration parser and dependencies can print to os.Stdout.
// A framed JSON RPC stream MUST be isolated from diagnostics; even one byte
// of a console log corrupts the FlClash IPC frame protocol.
//
// Capture the original stdout before rebinding os.Stdout to stderr. Only the
// exact original FlClash server.go writeFrame output uses this private pipe.
type velaStdioConn struct {
    rpcOutput io.Writer
}

func velaServeStdio() {
    protocolOutput := os.Stdout
    os.Stdout = os.Stderr
    serve(&velaStdioConn{rpcOutput: protocolOutput})
}

func (*velaStdioConn) Read(p []byte) (int, error) { return os.Stdin.Read(p) }
func (conn *velaStdioConn) Write(p []byte) (int, error) {
    return conn.rpcOutput.Write(p)
}
func (*velaStdioConn) Close() error { return nil }
func (*velaStdioConn) SetWriteDeadline(_ time.Time) error { return nil }
