# Vela-SHUO Android arm64 Preview

这是**可安装的 Android 预览 APK**，不是 Android VPN 客户端。

## 已有功能
- Vela-SHUO Flutter 手机布局、地球动画、主题切换、导航
- HTTPS 订阅解析（INTERNET 权限，仅公网 HTTPS）
- 粘贴分享链接、Clash/Mihomo YAML 等受支持的文本，离线解析节点
- 预览选择 Shadowsocks/VMess/VLESS/Trojan/Hysteria2 节点和协议
- 订阅链接不会写入 SharedPreferences 或诊断日志；节点原文仅在主动选择“加密保存本机”后写入 Android Keystore 保护的安全存储
- 重启自动尝试恢复明确保存的节点列表和所选节点（不启动代理）

## 尚未实现
- Android VpnService、前台 VPN 服务、Android Mihomo 原生内核
- 真实代理连接、测速、开机自启、后台连接与应用分流
- Android VpnService；加密存档已经实现，但自动同步订阅尚未实现
- Google Play 生产签名和商店发布

APK 仅适用于 arm64-v8a，包名 `com.shuowang.vela.preview`，显示名
`Vela-SHUO Preview`，与未来正式应用隔离。

CI 目前使用 Flutter Android 模板的默认 debug 签名密钥对 release-mode APK
签名，**不是生产签名**，未来正式版可能无法原地覆盖安装。
Android 主清单只新增 `INTERNET` 权限，禁用 Android 自动云端备份以避免加密存档密钥不匹配，不申请 VPN Service 权限。

CI：`.github/workflows/build.yml` → Android ARM64 preview APK (no VPN)。
需真机检查：安卓网络权限、订阅导入、界面适配、深浅色模式、返回键、
切换至后台再回来、卸载数据清理。Android 预览版不能代替真正的 VPN 客户端。
