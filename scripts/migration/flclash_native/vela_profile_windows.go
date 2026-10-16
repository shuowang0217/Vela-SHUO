//go:build windows && !(android && cgo)

package main

import (
    "fmt"
    "net/url"
    "strconv"
    "os"
    "path/filepath"
    "sync"
    "strings"

    "github.com/metacubex/mihomo/config"
    yaml "github.com/metacubex/mihomo/common/yaml"
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
                // FlClash defaults to RULE; do not silently turn every
                // imported profile into GLOBAL on every Android VPN restart.
                // A user's actual mode is applied separately with updateConfig.
                raw.Mode = T.Rule

                // FlClash lib/common/task.dart (makeRealProfileTask):
                // baseline DNS keys are patched ONLY if the source DNS
                // section is not enabled. A configured airport DNS remains
                // untouched unless the user explicitly enables DNS overrides.
                if !raw.DNS.Enable {
                    raw.DNS.Enable = true
                    raw.DNS.EnhancedMode = constant.DNSFakeIP
                    raw.DNS.NameServer = []string{
                        "https://doh.pub/dns-query",
                        "https://dns.alidns.com/dns-query",
                    }
                }
                raw.IPv6 = false
                raw.UnifiedDelay = true
                raw.TCPConcurrent = true
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
                // CRITICAL: RawConfig.Rule has yaml:"rules" but
                // json:"rule" (singular) in pinned Mihomo. Writing
                // JSON as config.yaml silently DROPPED the rule table on
                // reload: RULE fell back to DIRECT while GLOBAL worked.
                // Preserve all Mihomo YAML field names exactly.
                serialized, err := yaml.Marshal(raw)
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
                // UI hint only, not a routing override. FlClash's Mihomo
                // engine still evaluates every actual rule and group.
                matchGroup := ""
                for i := len(raw.Rule)-1; i >= 0; i-- {
                    fields := strings.SplitN(raw.Rule[i], ",", 3)
                    if len(fields) >= 2 &&
                        strings.EqualFold(strings.TrimSpace(fields[0]), "MATCH") {
                        matchGroup = strings.TrimSpace(fields[1])
                        break
                    }
                }
                response.success(map[string]any{
                    "match-group": matchGroup,
                    "groups": views.All,
                    "proxies": views.Proxies,
                    "raw-proxies": raw.Proxy,
                    // Native group attributes such as hidden do not always
                    // survive getProxies metadata; FlClash filters them.
                    "raw-proxy-groups": raw.ProxyGroup,
                    "provider-count": len(raw.ProxyProvider),
                })
            })
        },
    ))
}


// Download throughput uses FlClash-Custom's native probe.go measurement
// unchanged. Its private X-FlClash-Measure-Download switch returns a compact
// "actual_bytes,body_microseconds" string, not the binary response body.
// Vela only selects a target URL and adapts that upstream result to its UI.
type velaDownloadArgs struct {
    ProxyName string `json:"proxy-name"`
    TestURL string `json:"test-url"` // CI-only 127.0.0.1 fixture
}

const (
    velaDownloadLimit int64 = 1024 * 1024
    velaDownloadMinimum int64 = 256 * 1024
)

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

func velaCustomDownload(name, endpoint string) (bytes int64, micros int64, reason string) {
    // The Go Core's existing probe() owns the selected proxy, TLS, DNS,
    // response reading, and the body-only measurement. Its internal header
    // is removed before making the outbound HTTP request.
    measured := handleProbe(&ProbeParams{
        Url: endpoint,
        ProxyName: name,
        Timeout: 10000, // At most 4 endpoints; fit inside Dart's 55s RPC timeout.
        MaxBody: velaDownloadLimit,
        Headers: map[string]string{
            "X-FlClash-Measure-Download": "1",
            "Accept-Encoding": "identity",
            "Cache-Control": "no-cache",
        },
    })
    if measured == nil {
        return 0, 0, "busy"
    }
    if measured.Error != "" {
        if measured.Error == "timeout" { return 0, 0, "timeout" }
        return 0, 0, "network"
    }
    if measured.StatusCode != 200 {
        return 0, 0, "http_status"
    }
    values := strings.SplitN(measured.Body, ",", 2)
    if len(values) != 2 {
        return 0, 0, "invalid_sample"
    }
    n, errN := strconv.ParseInt(values[0], 10, 64)
    us, errUs := strconv.ParseInt(values[1], 10, 64)
    if errN != nil || errUs != nil || us <= 0 ||
        n < velaDownloadMinimum || n > velaDownloadLimit {
        return 0, 0, "short_sample"
    }
    return n, us, ""
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
                if lookupProxy(params.ProxyName) == nil {
                    response.success(map[string]any{"ok": false, "reason": "missing"})
                    return
                }
                // Public endpoints are bounded to a single MiB. A node may
                // block one CDN while allowing another, so try alternatives.
                endpoints := []string{
                    "https://speed.cloudflare.com/__down?bytes=1048576",
                    "https://cachefly.cachefly.net/1mb.test",
                    "https://proof.ovh.net/files/1Mb.dat",
                    "https://speed.hetzner.de/1MB.bin",
                }
                if params.TestURL != "" {
                    if !velaLocalDownloadURL(params.TestURL) {
                        response.failure("invalid_arguments", "Download fixture must use local loopback", nil)
                        return
                    }
                    endpoints = []string{params.TestURL}
                }
                lastReason := "no_sample"
                for _, endpoint := range endpoints {
                    received, elapsedUs, reason := velaCustomDownload(params.ProxyName, endpoint)
                    if reason != "" {
                        lastReason = reason
                        continue
                    }
                    mbps := float64(received) * 8 * 1000000 / float64(elapsedUs) / 1000000
                    if mbps <= 0 {
                        lastReason = "invalid_sample"
                        continue
                    }
                    response.success(map[string]any{
                        "ok": true, "bytes": received, "mbps": mbps,
                    })
                    return
                }
                response.success(map[string]any{"ok": false, "reason": lastReason})
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
                const concurrency = 16
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
                            // Match FlClash quick URLTest: never do a third
                            // sequential 6-second HTTP probe for each failed node.
                            // The fallback URL is only tried after a timeout;
                            // slow/offline nodes should not block a huge list.
                            for _, url := range urls {
                                timeout := 2800
                                if url != urls[0] { timeout = 1800 }
                                delay := handleTestDelay(&TestDelayParams{
                                    ProxyName: name, TestUrl: url, Timeout: timeout,
                                })
                                if delay != nil && delay.Value > 0 {
                                    result.Value = int64(delay.Value)
                                    result.Reason = ""
                                    break
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
