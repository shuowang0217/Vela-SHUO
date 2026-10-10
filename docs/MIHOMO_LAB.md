# Mihomo Lab — 独立 Windows 实验分支

分支：`experiment/mihomo-core`。**主分支仍使用已经实机验证的 sing-box**。本实验包是独立预览版，不替换正式版，也不改变地球、帆船、八套主题、首页连接按钮或 WinINet 代理恢复逻辑。

## 第一步实验能力

- Windows x64 压缩包内同时包含已固定版本的官方 `sing-box.exe` 和 SHA-256 校验的官方 `mihomo.exe`。
- 在「设置 → Mihomo 独立内核实验室」，使用已导入订阅和已经选中的节点生成精简配置；目前转换支持 Shadowsocks、VMess、VLESS、Trojan、Hysteria2 的基本及部分 TLS/Reality/WS/gRPC 参数。不兼容节点会被拒绝或跳过，不会关闭 TLS 验证。
- 实验 Mihomo 的 HTTP/mixed 代理只监听 `127.0.0.1:20818`，本地 REST 控制 API 只监听 `127.0.0.1:20819`，使用随机生成的会话级密钥 `Authorization: Bearer <secret>`。主 sing-box 监听仍为 `127.0.0.1:20808`。
- 点击「启动实验内核并验证 HTTPS」先做 Mihomo 官方配置自检、检查端口占用、启动隔离内核、调用经认证的本机 API 验证策略组选中节点，然后通过实验代理请求固定的 HTTPS 204 检测地址。只有成功才显示运行中。
- 运行中可从实验节点下拉框调用 Mihomo `PUT /proxies/VELA_SELECT`，再次查询确认并进行 HTTPS 验证；失败时尝试恢复旧策略选择。
- 停止时关闭实验进程并删除本机临时配置。实验启动不会修改 Windows 系统代理，不会影响已连接的主 sing-box 内核。测试失败不会被显示成连接成功。

## 为什么目前不切换默认内核

Mihomo Selector 改变后续新连接使用的出口，不保证已经存在的 TCP/UDP 连接不中断。它和 Mihomo/Mihomo Meta 定制的实时测速 API 是两个不同的验证工作。这一轮只做控制链路和协议基本兼容性验证，不能宣称已经复刻 FlClash-Custom 的全套测速度与无缝热切换。

需要 Windows 实机验收：不同类型订阅节点的配置自检、真实 YouTube 访问、实验开关、Mihomo 切换后的 HTTPS 检查与先前连接的表现、意外退出的配置清理、安全授权，以及正式版原代理的完整恢复。**目前不允许 Mihomo 自动接管 Windows 系统代理**，测试不会覆盖可用版本的网络配置。

实验配置位于 `%LOCALAPPDATA%\Vela-SHUO\MihomoLab\lab.json`，其中包含节点凭据及本地控制密钥；启动后正常关闭或下次打开软件会尝试删除。强制关机/强杀后可能短暂留存在本地磁盘，在正式启用前需继续强化异常清理机制。

## 官方 Mihomo

官方项目：https://github.com/MetaCubeX/mihomo

版本：v1.19.32（`mihomo-windows-amd64-compatible-v1.19.32.zip`，SHA-256 `974a4d7ad69aed27aa2e8f91d61113573c14dadb14562c63e58effabf59816f0`）

使用官方未经改动的内核及许可证，参见 `third_party/mihomo/NOTICE.md`。

后续计划：把 **FlClash-Custom 的策略组选线** 与运行时节点管理适配到 Mihomo 分支，同时保留现有 Smart Engine 的真实速度算法，不在未通过 Windows 实机测试之前切换默认内核。
