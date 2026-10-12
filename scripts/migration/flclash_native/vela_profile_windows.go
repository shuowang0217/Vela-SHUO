//go:build windows && !(android && cgo)

package main

import (
    "encoding/json"
    "fmt"
    "os"
    "path/filepath"

    "github.com/metacubex/mihomo/config"
    "github.com/metacubex/mihomo/constant"
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
                if !isInit.Load() {
                    response.failure("not_initialized", "FlClash core is not initialized", nil)
                    return
                }
                if len(params.Content) == 0 || len(params.Content) > 16*1024*1024 {
                    response.failure("invalid_profile", "Profile is empty or exceeds 16 MB", nil)
                    return
                }
                raw, err := config.UnmarshalRawConfig([]byte(params.Content))
                if err != nil {
                    response.failure("invalid_profile", "Mihomo rejected the subscription YAML", nil)
                    return
                }
                // FlClash app settings, not remote subscriptions, own listeners
                // and privilege-affecting settings. Do not let a provider turn
                // the local client into an externally reachable proxy server.
                raw.Port, raw.SocksPort, raw.RedirPort, raw.TProxyPort = 0, 0, 0, 0
                raw.MixedPort = 20808
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
                serialized, err := json.Marshal(raw)
                if err != nil {
                    response.failure("invalid_profile", "Mihomo could not encode profile", nil)
                    return
                }
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
                result := handleSetupConfig(defaultSetupParams())
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
                views := handleGetProxies()
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
