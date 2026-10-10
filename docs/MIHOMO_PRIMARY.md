# Mihomo 主内核迁移（2026-10-10）

原实验分支与主页 sing-box 双核已合并为单一 Mihomo 路径，不保留 sing-box 打包依赖。

- 主运行：`VelaCoreController` 管理 `core/mihomo.exe`，自检使用 `mihomo -t -d <目录> -f <json>`，运行使用 `mihomo -d <目录> -f <json>`。
- 本地混合代理仍监听 `127.0.0.1:20808`；WinINet 恢复日志沿用以前的端口，防止升级时破坏正在等待恢复的代理。
- 订阅：`VelaMihomoConfigBuilder` 用白名单字段转换受支持的 SS/VMess/VLESS/Trojan/Hysteria2 节点为 JSON（YAML 子集），仅使用本地 mixed-port、策略组 VELA_SELECT。unsupported 节点不降低 TLS 安全策略。
- 智能优选：每次测量使用单独随机回环端口、临时配置和 Mihomo 进程，实测延迟与 HTTP 下载。主系统代理不动。
- 无需在正式 UI 保留独立实验室；只运行一个正式内核。为避免暴露额外控制端口，正式连接和测速配置不启用本地 REST API。
- 旧的 `sing-box JSON` 订阅解析器仅作为输入兼容格式存在，**不**作为运行内核，也不将原生 sing-box 配置提交给 Mihomo。
- 不支持 TUN/虚拟网卡，不宣称无损 TCP/UDP 热切换或完整 FlClash-Custom API 兼容性。

官方版本：MetaCubeX/mihomo v1.19.32，`mihomo-windows-amd64-compatible-v1.19.32.zip`，SHA-256 `974a4d7ad69aed27aa2e8f91d61113573c14dadb14562c63e58effabf59816f0`。

Windows CI 必须在验证所有 Flutter 单测后完成 Release 打包。实机验收建议覆盖真实订阅、YouTube HTTPS、手动断开与异常恢复、多个节点测速、系统代理被其他程序修改后的行为。
