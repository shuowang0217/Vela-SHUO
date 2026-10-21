# Vela 1.10.0 正式版 · 双端对齐

**正式版本：1.10.0（构建号 58）**，基于经过实机验收的「油画罗盘 / 航行开关」版本 `feature/android-compass-fixed-label` 定版，不包含后来测试的「扬帆」图标或名称。

## Windows 与 Android 同版本发布

- **Android ARM64**：`Vela-v1.10.0-Android-arm64.apk`；应用 ID `com.shuowang.vela`，Android `versionName=1.10.0`、`versionCode=58`，使用已有长期正式签名。可覆盖此前相同签名的 1.9.0 测试构建号 53–57，保留机场数据。
- **Windows x64**：`Vela-v1.10.0-Windows-x64.zip`；程序 `Vela.exe`；Flutter 应用版本同为 1.10.0+58，携带独立的 FlClash Go 核心和 Mihomo 可执行文件。关闭旧版程序后完整解压替换。
- 两端共享同一套 Vela Flutter 界面、机场和节点处理逻辑、网络内核版本固定值。Android 使用真实 VPN TUN，Windows 使用本机系统代理；两个操作系统的底层代理接入方式本来不同，不应把它们误认为同一种设备级 VPN。
- 应用内版本检测升级为 `VelaUpdateService.currentVersion = 1.10.0`，与 GitHub 标签 `v1.10.0` 对齐。

## Android 固定油画罗盘快捷操作

- 三星 One UI 长按 Vela 应用图标，提供**一个**原生快捷入口 **「航行开关」**，图标来自 Vela 原油画导航罗盘。
- 点击时不会打开 Vela 主界面；未连接时启动 VPN 并短暂提示「正在启航…」，已连接时断开 VPN 并短暂提示「正在返航…」。
- 菜单名称不再随连接状态变动，避免已弹开的三星菜单停留在过期标题。
- 第一次安装后需正常打开 Vela 一次，让原生动态快捷入口注册，并缓存当前节点选择；首次 VPN 授权仍按 Android 系统流程办理。
- 没有旧油画小组件，也没有「扬帆」版本使用的油画帆船快捷图标。

## 其余继承与安全性

继承 1.9.0 的日夜油画地图、航海视觉、机场管理、节点延迟测试、规则/全局/直连模式、测速通知和订阅恢复。Windows、Android 都保留经固定 Git 提交版本验证的 FlClash/Mihomo 原生核心。

## 发布与完整性

CI 必须依次通过 Flutter 静态分析/回归测试、Windows x64 全部原生构建与业务端到端检测、Android ARM64 VPN 构建、永久签名证书指纹验证、两端 SHA-256 文件哈希及产物 ZIP/APK 结构验证，才在 `release/v1.10.0` 分支自动创建 `v1.10.0` 正式 Release。既有 v1.9.0 Release 不覆盖。
