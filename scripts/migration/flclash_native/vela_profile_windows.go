//go:build windows && !(android && cgo)

package main

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "net/url"
    "io"
    "strconv"
    "os"
    "path/filepath"
    "time"
    "sync"
    "strings"

    "github.com/metacubex/mihomo/config"
    "github.com/metacubex/mihomo/component/ca"
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


// A bounded, node-pinned throughput measurement using the same FlClash
// probeDialer and Mihomo CA configuration as the original Go probe. Never
// serialize downloaded binary data into a JSON RPC response.
type velaDownloadArgs struct {
    ProxyName string `json:"proxy-name"`
    // Only used by the deterministic CI loopback SOCKS5 fixture.
    TestURL string `json:"test-url"`
}

const (
    velaDownloadLimit int64 = 1024 * 1024
    velaDownloadMinimum int64 = 256 * 1024
    velaDownloadTimeout = 15 * time.Second
)

// Local test URLs must not redirect or resolve via a non-loopback hostname.
// The production UI never sets test-url; it uses fixed public HTTPS targets.
func velaLocalDownloadURL(raw string) bool {
    parsed, err := url.Parse(raw)
    if err != nil || parsed.Scheme != "http" ||
        parsed.Hostname() != "127.0.0.1" || parsed.User != nil ||
        parsed.Fragment != "" || parsed.Opaque != "" {
        return false
    }
    port, err := strconv.Atoi(parsed.Port())
    return err == nil && port > 0 && port <= 65535
}

// Use the selected proxy's DialContext, NEVER the host's direct connection.
// Time only the bounded response BODY: DNS, TLS and the response's first-byte
// delay must not distort actual download throughput.
func velaReadDownload(ctx context.Context, proxy constant.Proxy, endpoint string) (int64, time.Duration) {
    tlsConfig, err := ca.GetTLSConfig(ca.Option{})
    if err != nil {
        return 0, 0
    }
    dialer := &probeDialer{proxy: proxy}
    transport := &http.Transport{
        DialContext: dialer.dial,
        TLSClientConfig: tlsConfig,
        TLSHandshakeTimeout: 10 * time.Second,
        DisableCompression: true,
        MaxIdleConns: 1,
    }
    defer transport.CloseIdleConnections()
    client := &http.Client{
        Transport: transport,
        CheckRedirect: func(*http.Request, []*http.Request) error {
            return http.ErrUseLastResponse
        },
    }
    request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
    if err != nil {
        return 0, 0
    }
    request.Header.Set("Accept-Encoding", "identity")
    request.Header.Set("Cache-Control", "no-cache")
    response, err := client.Do(request)
    if err != nil {
        return 0, 0
    }
    defer response.Body.Close()
    if response.StatusCode != http.StatusOK &&
        response.StatusCode != http.StatusPartialContent {
        return 0, 0
    }
    if response.Header.Get("Content-Encoding") != "" ||
        strings.Contains(strings.ToLower(response.Header.Get("Content-Type")), "text/html") {
        return 0, 0
    }
    started := time.Now()
    // io.Copy to Discard uses constant memory and never returns the payload
    // through the RPC frame. LimitReader bounds traffic even for huge files.
    count, _ := io.Copy(io.Discard, io.LimitReader(response.Body, velaDownloadLimit))
    elapsed := time.Since(started)
    // A remote origin can close early or report a wrong Content-Length.
    // Enough genuine bytes received over a pinned node are still a sample.
    if count < velaDownloadMinimum || count > velaDownloadLimit ||
        elapsed <= 0 || ctx.Err() != nil {
        return 0, 0
    }
    return count, elapsed
}

func init() {
    registerMethod(CoreMethod("velaTestDownload"), withArguments(
        func(params *velaDownloadArgs, response MethodResponse) {
            safeGo(response, func() {
                if !isInit.Load() {
                    response.failure("not_initialized", "FlClash core is not ready", nil)
                    return
                }
                if params.ProxyName == "" {
                    response.failure("invalid_arguments", "Missing selected node", nil)
                    return
                }
                proxy := lookupProxy(params.ProxyName)
                if proxy == nil {
                    response.success(map[string]any{"ok": false, "reason": "missing"})
                    return
                }
                endpoints := []string{
                    "https://speed.cloudflare.com/__down?bytes=1048576",
                    "https://cachefly.cachefly.net/1mb.test",
                    "https://proof.ovh.net/files/1Mb.dat",
                }
                if params.TestURL != "" {
                    if !velaLocalDownloadURL(params.TestURL) {
                        response.failure("invalid_arguments", "Download fixture must use local loopback", nil)
                        return
                    }
                    endpoints = []string{params.TestURL}
                }
                for _, endpoint := range endpoints {
                    ctx, cancel := context.WithTimeout(context.Background(), velaDownloadTimeout)
                    if !acquireSlot(ctx, probeSlots) {
                        cancel()
                        continue
                    }
                    count, elapsed := velaReadDownload(ctx, proxy, endpoint)
                    <-probeSlots
                    cancel()
                    if count < velaDownloadMinimum {
                        continue
                    }
                    mbps := float64(count) * 8 / elapsed.Seconds() / 1000000
                    if mbps <= 0 {
                        continue
                    }
                    response.success(map[string]any{
                        "ok": true,
                        "bytes": count,
                        "mbps": mbps,
                    })
                    return
                }
                response.success(map[string]any{"ok": false, "reason": "no_sample"})
            })
        },
    ))
}

// Vela's GUI must not multiply thousands of tiny native IPC calls when a
// subscription has 40-300 proxies. Let the original FlClash Go core own one
// bounded batch. The actual latency is still calculated exclusively by
// Mihomo URLTest or FlClash's built-in probe, never a Dart stopwatch.
type velaLatencyBatchArgs struct {
    Names []string `json:"names"`
    TestURL string `json:"test-url"`
}
type velaLatencyBatchRow struct {
    Name string `json:"name"`
    Value int64 `json:"value"`
    Reason string `json:"reason,omitempty"`
}

func init() {
    registerMethod(CoreMethod("velaTestLatencies"), withArguments(
        func(params *velaLatencyBatchArgs, response MethodResponse) {
            safeGo(response, func() {
                if !isInit.Load() {
                    response.failure("not_initialized", "FlClash not ready", nil)
                    return
                }
                if len(params.Names) == 0 || len(params.Names) > 512 {
                    response.failure("invalid_arguments", "Invalid batch size", nil)
                    return
                }

                // Local-only override exists for a deterministic CI
                // test using a 204 fixture. Production always uses the
                // original public HTTPS probes; remote hosts are forbidden.
                if params.TestURL != "" &&
                    !strings.HasPrefix(params.TestURL, "http://127.0.0.1:") {
                    response.failure("invalid_arguments", "Invalid test endpoint", nil)
                    return
                }
                urls := []string{
                    "https://www.gstatic.com/generate_204",
                    "https://cp.cloudflare.com/generate_204",
                }
                if params.TestURL != "" {
                    urls = []string{params.TestURL}
                }
                rows := make([]velaLatencyBatchRow, len(params.Names))
                jobs := make(chan int)
                var workers sync.WaitGroup
                const concurrency = 8
                for n := 0; n < concurrency; n++ {
                    workers.Add(1)
                    go func() {
                        defer workers.Done()
                        for index := range jobs {
                            name := params.Names[index]
                            result := velaLatencyBatchRow{
                                Name: name, Value: -1, Reason: "unreachable",
                            }
                            if name == "" || lookupProxy(name) == nil {
                                result.Reason = "missing"
                                rows[index] = result
                                continue
                            }
                            for _, url := range urls {
                                delay := handleTestDelay(&TestDelayParams{
                                    ProxyName: name, TestUrl: url, Timeout: 6000,
                                })
                                if delay != nil && delay.Value > 0 {
                                    result.Value = int64(delay.Value)
                                    result.Reason = ""
                                    break
                                }
                            }
                            if result.Value < 0 {
                                // Same FlClash Go probeDialer, with no extra
                                // proxy configuration and NO guessed latency.
                                probeURL := "https://cp.cloudflare.com/generate_204"
                                if params.TestURL != "" { probeURL = params.TestURL }
                                probe := handleProbe(&ProbeParams{
                                    Url: probeURL,
                                    ProxyName: name, Timeout: 6000,
                                    MaxBody: 0,
                                    Headers: map[string]string{},
                                })
                                if probe == nil {
                                    result.Reason = "busy"
                                } else if probe.Error != "" {
                                    result.Reason = probe.Error
                                } else if probe.StatusCode == 204 && probe.Delay >= 0 {
                                    result.Value = probe.Delay
                                    if result.Value == 0 { result.Value = 1 }
                                    result.Reason = ""
                                } else {
                                    result.Reason = "bad_status"
                                }
                            }
                            rows[index] = result
                        }
                    }()
                }
                for i := range params.Names { jobs <- i }
                close(jobs)
                workers.Wait()
                response.success(rows)
            })
        },
    ))
}
