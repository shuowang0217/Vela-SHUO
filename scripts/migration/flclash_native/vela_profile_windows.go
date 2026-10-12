//go:build windows && !(android && cgo)

package main

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "os"
    "path/filepath"
    "time"

    "github.com/metacubex/mihomo/config"
    "github.com/metacubex/mihomo/constant"
    T "github.com/metacubex/mihomo/tunnel"
)

// A Vela-specific IPC entry point, delegating ALL interpretation and network
// state to the pinned FlClash/Mihomo Go implementation. Vela never translates
// Reality, gRPC, WS, TUIC, provider definitions, or rules into its own grammar.
type velaImportArgs struct {
    Content string `json:"content"`
}

func init() {
    registerMethod(CoreMethod("velaLoadProfile"), withArguments(
        func(params *velaImportArgs, response MethodResponse) {
            safeGo(response, func() {
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=profile-enter")
                if !isInit.Load() {
                    response.failure("not_initialized", "FlClash core is not initialized", nil)
                    return
                }
                if len(params.Content) == 0 || len(params.Content) > 16*1024*1024 {
                    response.failure("invalid_profile", "Profile is empty or exceeds 16 MB", nil)
                    return
                }
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=unmarshal-enter")
                raw, err := config.UnmarshalRawConfig([]byte(params.Content))
                if err != nil {
                    response.failure("invalid_profile", "Mihomo rejected the subscription YAML", nil)
                    return
                }
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=unmarshal-done")
                // FlClash app settings, not remote subscriptions, own listeners
                // and privilege-affecting settings. Do not let a provider turn
                // the local client into an externally reachable proxy server.
                raw.Port, raw.SocksPort, raw.RedirPort, raw.TProxyPort = 0, 0, 0, 0
                raw.MixedPort = 20808
                // Vela's single-node Connect action corresponds to FlClash
                // GLOBAL mode, NOT the imported subscription's RULE mode.
                // Otherwise a selected proxy can be ignored by MATCH,DIRECT.
                // FlClash/Mihomo itself still owns every routing decision.
                raw.Mode = T.Global
                raw.AllowLan = false
                raw.BindAddress = "127.0.0.1"
                raw.ExternalController = ""
                raw.ExternalControllerTLS = ""
                raw.ExternalControllerPipe = ""
                raw.ExternalControllerUnix = ""
                raw.ExternalDohServer = ""
                raw.ExternalUI = ""
                raw.Authentication = nil
                raw.Listeners = nil
                raw.Tunnels = nil
                raw.ShadowSocksConfig = ""
                raw.VmessConfig = ""
                raw.Tun.Enable = false
                raw.IPTables.Enable = false
                raw.TuicServer.Enable = false
                raw.NTP.WriteToSystem = false
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=serialize-enter")
                serialized, err := json.Marshal(raw)
                if err != nil {
                    response.failure("invalid_profile", "Mihomo could not encode profile", nil)
                    return
                }
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=serialize-done")
                path := filepath.Join(constant.Path.HomeDir(), "config.yaml")
                backup, readErr := os.ReadFile(path)
                if readErr != nil && !os.IsNotExist(readErr) {
                    response.failure("profile_storage", "Cannot read current FlClash configuration", nil)
                    return
                }
                tmp, err := os.CreateTemp(constant.Path.HomeDir(), "vela-profile-*.tmp")
                if err != nil {
                    response.failure("profile_storage", "Cannot stage new FlClash configuration", nil)
                    return
                }
                tempPath := tmp.Name()
                defer os.Remove(tempPath)
                if _, err = tmp.Write(serialized); err == nil {
                    err = tmp.Chmod(0600)
                }
                if closeErr := tmp.Close(); err == nil {
                    err = closeErr
                }
                if err != nil {
                    response.failure("profile_storage", "Cannot store FlClash configuration", nil)
                    return
                }
                if err = os.Rename(tempPath, path); err != nil {
                    response.failure("profile_storage", "Cannot apply staged FlClash configuration", nil)
                    return
                }
                // Use the EXACT same FlClash Go config application/validation,
                // including Mihomo's proxy provider and rule-provider parser.
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=apply-enter")
                result := handleSetupConfig(defaultSetupParams())
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=apply-return")
                if result != "" {
                    if readErr == nil {
                        _ = os.WriteFile(path, backup, 0600)
                        _ = handleSetupConfig(defaultSetupParams())
                    } else {
                        _ = os.Remove(path)
                        _ = handleStopListener()
                    }
                    response.failure("profile_invalid", fmt.Sprintf("Mihomo config apply failed (size=%d)", len(params.Content)), nil)
                    return
                }
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=get-proxies-enter")
                views := handleGetProxies()
                fmt.Fprintln(os.Stderr, "VELA_DIAG stage=get-proxies-return")
                if _, exists := views.Proxies["GLOBAL"]; !exists {
                    response.failure("no_global", "Mihomo global selector missing", nil)
                    return
                }
                if len(views.Proxies) == 0 {
                    response.failure("no_proxies", "FlClash core returned no proxies", nil)
                    return
                }
                response.success(map[string]any{
                    "groups": views.All,
                    "proxies": views.Proxies,
                    "raw-proxies": raw.Proxy,
                    "provider-count": len(raw.ProxyProvider),
                })
            })
        },
    ))
}


// The Vela speed-test button delegates its bounded sample to FlClash's
// existing runProbe/probeDialer. This adds only timing/byte metadata; the
// networking algorithm, TLS, proxy choice and connection pool remain Mihomo's.
type velaDownloadArgs struct {
    ProxyName string `json:"proxy-name"`
}

func init() {
    registerMethod(CoreMethod("velaTestDownload"), withArguments(
        func(params *velaDownloadArgs, response MethodResponse) {
            safeGo(response, func() {
                if params.ProxyName == "" {
                    response.failure("invalid_arguments", "Missing selected node", nil)
                    return
                }
                // The original FlClash Go probeDialer owns DNS, TLS,
                // routing and credentials. Only the sample URLs differ.
                // The old single-CDN exact-1MiB rule marked every other
                // valid response failed when its origin truncated output.
                const sampleSize int64 = 1024 * 1024
                const minSample int = 256 * 1024
                endpoints := []string{
                    "https://speed.cloudflare.com/__down?bytes=1048576",
                    "https://proof.ovh.net/files/1Mb.dat",
                    "https://speed.hetzner.de/1MB.bin",
                }
                for _, endpoint := range endpoints {
                    started := time.Now()
                    result := runProbe(context.Background(), probeRequest{
                        method: http.MethodGet,
                        url: endpoint,
                        proxyName: params.ProxyName,
                        timeout: 15 * time.Second,
                        maxBody: sampleSize,
                        noRedirect: true,
                        headers: map[string]string{
                            "Accept-Encoding": "identity",
                            "Cache-Control": "no-cache",
                        },
                    })
                    seconds := time.Since(started).Seconds()
                    if result == nil || result.Error != "" ||
                        result.StatusCode != http.StatusOK ||
                        len(result.Body) < minSample || seconds <= 0 {
                        continue
                    }
                    transferred := len(result.Body)
                    response.success(map[string]any{
                        "ok": true,
                        "bytes": transferred,
                        "mbps": float64(transferred) * 8 / seconds / 1000000,
                    })
                    return
                }
                response.success(map[string]any{"ok": false})
            })
        },
    ))
}
