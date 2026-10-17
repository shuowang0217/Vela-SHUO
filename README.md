# Vela

**正式版本：1.7.0**（Android 构建号 33）· Windows x64 / Android ARM64

Vela 保留已验证的原创 UI，网络、规则、分组、DNS 和代理协议交由原生
[FlClash / Mihomo](https://github.com/shuowang0217/FlClash-Custom) 核心负责。
源码仓库暂仍使用 `Vela-SHUO` 作为内部历史标识，不影响产品名称。

## 正式发布与更新

官方稳定版下载入口：[GitHub Releases](https://github.com/shuowang0217/Vela-SHUO/releases/latest)。

- Android：`Vela-v1.7.0-Android-arm64.apk`，安装后应用名称为 **Vela**。
  1.5.0 起使用长期固定的应用 ID `com.shuowang.vela`、正式签名证书和
  递增的 Android versionCode；本版使用 33，可覆盖已安装的 1.7.4 测试版（内部码 32）；后续安装同签名的新 APK 可覆盖升级，
  保留当前机场与偏好数据。
- Windows：`Vela-v1.7.0-Windows-x64.zip`，完整解压后运行
  `Vela.exe`。使用「安全退出」关闭旧版，再更新程序文件。
  原 `Vela-SHUO` 目录中的用户数据路径保留，便于升级兼容。
- Vela 设置页提供「检查更新」：查看正式 GitHub Release，并由用户确认
  下载相应平台包。不会在后台静默安装可执行文件。

**从 1.4.7 Beta 升级的特别说明：** 旧 Android 安装包使用
`com.shuowang.vela.vpn.beta` 及每次构建可能变化的 Debug 签名，
不能保证覆盖升级。正式版 1.5.0 使用新的稳定应用 ID，第一次迁移
需要从旧版重新导入机场配置；验证新版本正常后再卸载旧版。
请勿提前卸载旧版，以免丢失已加密保存的订阅。

**签名复用：** 1.5.0 直接使用 FlClash-Custom 仓库已有的加密签名证书。
在 Vela-SHUO 的 GitHub Actions Repository secrets 中配置同名
`SHUO_SIGNING_PASSWORD`（值必须与旧仓库完全一致），即可恢复同一证书。
签名密码只在 GitHub Actions 运行环境读取，不会写入仓库或安装包。

**发布要求：** 只有配置长期保管的 Android 正式签名密钥并通过
Flutter 测试、Windows/Android 构建及 SHA-256 和证书校验后，
CI 才允许发布 `v1.7.0`。未配置密钥时，不会伪装生成可升级的正式 APK。
参见 [1.7.0 正式发布说明](docs/RELEASE_v1.7.0.md) 和 [固定签名配置](docs/RELEASE_v1.5.0.md)。

## 1.7.0 定版说明

本版整合并保留 v1.2.0、v1.3.0、v1.4.0、v1.5.0、v1.6.0 的历史定版，同时纳入验证通过的水彩云层、北京航线起点、英文手绘地图名称和顶部毛玻璃通知。下载测速采用此前稳定的原始实现。

**由开发版转换正式版**：之前的测试包曾使用更高的显示版本号（如 1.7.4），因此应用内只比较语义版本号的更新检测可能不会提示 1.7.0；请手动从 GitHub Releases 安装。Android 内部构建号 33 不会低于既有 1.7.4 测试版的 32。

## 功能

- 本地订阅保存、机场切换、节点与策略组选择、节点测速。
- 规则、全局和直连模式均由 FlClash/Mihomo 原生核心处理。
- Android 原生 VPN / TUN，常驻机场名称与双向实时速度通知。
- Windows 便携运行、安全退出时还原系统代理。
- 固定版本号、正式发行包和应用内新版本检查。
