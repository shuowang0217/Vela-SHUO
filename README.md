# Vela

**正式版本目标：1.5.0** · Windows x64 / Android ARM64

Vela 保留已验证的原创 UI，网络、规则、分组、DNS 和代理协议交由原生
[FlClash / Mihomo](https://github.com/shuowang0217/FlClash-Custom) 核心负责。
源码仓库暂仍使用 `Vela-SHUO` 作为内部历史标识，不影响产品名称。

## 正式发布与更新

官方稳定版下载入口：[GitHub Releases](https://github.com/shuowang0217/Vela-SHUO/releases/latest)。

- Android：`Vela-v1.5.0-Android-arm64.apk`，安装后应用名称为 **Vela**。
  1.5.0 起使用长期固定的应用 ID `com.shuowang.vela`、正式签名证书和
  递增的 Android versionCode；后续安装相同签名的新 APK 可覆盖升级，
  保留当前机场与偏好数据。
- Windows：`Vela-v1.5.0-Windows-x64.zip`，完整解压后运行
  `Vela.exe`。使用「安全退出」关闭旧版，再更新程序文件。
  原 `Vela-SHUO` 目录中的用户数据路径保留，便于升级兼容。
- Vela 设置页提供「检查更新」：查看正式 GitHub Release，并由用户确认
  下载相应平台包。不会在后台静默安装可执行文件。

**从 1.4.7 Beta 升级的特别说明：** 旧 Android 安装包使用
`com.shuowang.vela.vpn.beta` 及每次构建可能变化的 Debug 签名，
不能保证覆盖升级。正式版 1.5.0 使用新的稳定应用 ID，第一次迁移
需要从旧版重新导入机场配置；验证新版本正常后再卸载旧版。
请勿提前卸载旧版，以免丢失已加密保存的订阅。

**发布要求：** 只有配置长期保管的 Android 正式签名密钥并通过
Flutter 测试、Windows/Android 构建及 SHA-256 和证书校验后，
CI 才允许发布 `v1.5.0`。未配置密钥时，不会伪装生成可升级的正式 APK。
参见 [1.5.0 发布说明与签名配置](docs/RELEASE_v1.5.0.md)。

## 功能

- 本地订阅保存、机场切换、节点与策略组选择、节点测速。
- 规则、全局和直连模式均由 FlClash/Mihomo 原生核心处理。
- Android 原生 VPN / TUN，常驻机场名称与双向实时速度通知。
- Windows 便携运行、安全退出时还原系统代理。
- 固定版本号、正式发行包和应用内新版本检查。
