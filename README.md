# Vela-SHUO

Windows x64 优先的 Flutter 网络工具，独立原创 UI「一帆越洋，尽览四方。」。

## 默认内核：Mihomo

从 2026-10-10 起，Vela-SHUO 的首页真实一键连接、订阅节点配置和智能优选测速**只使用 Mihomo**。Windows ZIP 仅捆绑官方 SHA-256 校验的 Mihomo v1.19.32（`core/mihomo.exe`），不再捆绑或启动 sing-box。旧 Mihomo 实验室入口合并至正式连接路径。现有地球、帆船、主题、导航、按钮与云层视觉保持不变。

- 首页连接先以 Mihomo `-t` 自检配置，启动本机 `127.0.0.1:20808` mixed 代理，经真实 HTTPS 验证后才征得用户授权接管 Windows 系统代理。
- 断开、程序意外退出等情况遵循原 WinINet 代理恢复日志；不擅自覆盖其他程序后来设置的代理。
- HTTPS 订阅与导入的 Clash/Mihomo YAML、历史 sing-box JSON **节点数据**仍可解析，但运行时始终转换为 Mihomo JSON 配置。只开放已支持的节点协议，不允许订阅定义系统监听/TUN。
- 智能测试每次启动隔离的临时 Mihomo 进程，完成 HTTPS 测延迟与 1 MiB 采样下载，清理凭据和临时端口。不修改正在使用的系统代理。
- 本地直连测试不等于远程网络连通；没有可用订阅节点时不会显示真实连接成功。
- 系统代理仍为显式授权，不提供 TUN 系统级隧道。已经建立的连接不保证在切换节点时保持不中断；节点自动优选目前仅在断开期间执行。

云端构建：`.github/workflows/build.yml`，只打包 Windows x64 Release 的 EXE、Flutter DLL 和数据以及 `core/mihomo.exe`。Android 暂停构建，等待 Windows 实机验证。更详细的迁移说明见 `docs/MIHOMO_PRIMARY.md`。

## 注意事项

本项目的桌面演示节点和动画不应与真实网络测速混淆。Windows 端的 HTTPS 真实代理验证只表明检查目标可达，不代表任意网站均可访问。首次使用应先在设置页导入订阅、选择节点再连接。Mihomo 包含第三方版权，请保留随包的 LICENSE 和第三方 NOTICE。
