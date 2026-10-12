//go:build windows && !(android && cgo)

package main

import (
    "encoding/hex"
    "errors"
    "net"
    "strings"
    "time"
)

// Vela hosts an ephemeral loopback socket rather than using the child's
// stdout. FlClash's ORIGINAL server.go frame reader/writer and method
// dispatcher run unchanged over the authenticated TCP connection.
//
// An unguessable 256-bit rendezvous preface prevents other local processes
// from accidentally attaching to the Vela controller's RPC listener.
func velaServeLoopback(argument string) error {
    spec := strings.TrimPrefix(argument, "--vela-loopback=")
    parts := strings.SplitN(spec, "@", 2)
    if len(parts) != 2 {
        return errors.New("invalid Vela IPC arguments")
    }
    token, err := hex.DecodeString(parts[0])
    if err != nil || len(token) != 32 {
        return errors.New("invalid Vela IPC handshake")
    }
    host, _, err := net.SplitHostPort(parts[1])
    if err != nil || host != "127.0.0.1" {
        return errors.New("Vela IPC must bind loopback only")
    }
    socket, err := net.DialTimeout("tcp", parts[1], 10*time.Second)
    if err != nil {
        return err
    }
    if err = socket.SetWriteDeadline(time.Now().Add(5*time.Second)); err != nil {
        socket.Close()
        return err
    }
    if _, err = socket.Write(token); err != nil {
        socket.Close()
        return err
    }
    _ = socket.SetWriteDeadline(time.Time{})
    serve(socket)
    return nil
}
