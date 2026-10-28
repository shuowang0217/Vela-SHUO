# Vela

**正式版 1.11.0**（Android build 63） · Windows x64 / Android ARM64

原创航海油画风格网络客户端，使用固定版本的原生 FlClash / Mihomo 内核处理代理、规则与 DNS，源码仓库仍为 `Vela-SHUO`。

## 正式版下载

[GitHub Releases · 最新 Vela](https://github.com/shuowang0217/Vela-SHUO/releases/latest)

- **Android**：`Vela-v1.11.0-Android-arm64.apk`；固定应用 ID `com.shuowang.vela`、长期正式签名、versionCode=63。可覆盖较低 build 的同签名安装版，正常保留机场数据。
- **Windows**：`Vela-v1.11.0-Windows-x64.zip`；安全退出旧版，完整解压后运行 `Vela.exe`，请勿只替换 EXE。
- **版本更新**：应用只提示 GitHub 最新正式 Release，不在后台静默下载安装。

## 1.11.0 重要改进

- **真实出口 IP**：在原有右上角连接模块显示油画风格国旗和真实公网 IP；不能取得检测结果时显示 `timeout`。
- **原生多来源检测**：复用 FlClash/Mihomo `outboundIp`，8 个 HTTPS 数据源，连接后自动检测及失败重试；每 2 分钟刷新一次，切换窗口不会反复清空成功结果。
- **油画小国旗**：本地图形叠加油彩笔触和画布浮雕纹理，不依赖系统 emoji 字体。
- **原有特色保留**：日夜油画地图、机场订阅、延迟测速、规则/全局/直连、Android VPN 与三星 One UI「航行开关」快捷操作。

完整说明：[Vela v1.11.0 发布说明](docs/RELEASE_v1.11.0.md)

## 1.9.0 改进

- **机场列表**：正在使用的机场优先排列，轻微选中高亮。Windows 保留双列宽度，同排卡片等高；手机保持单列统一基础高度。
- **Windows 装饰航线**：兼容 CRLF 与 LF 海洋网格换行，恢复海上轨迹与航行小船显示。
- **Android 速度通知**：实际油画海景（海鸥、帆船、海面），独立显示风速和航速，不重复系统图标，遵守系统外壳显示限制。
- **代理模式**：规则、全局、直连切换使用 Android 原生持久化与读取确认；规则设置弹窗不再压暗地图。
- **机场订阅自动更新**：15 分钟起、应用**运行期间**定时检查，失败按间隔重试，回到前台时复查；退出软件后不保证后台自动更新。
- **延迟测速**：状态文案统一为 Vela，仍由原生 Mihomo 内核提供测量结果。

海图中的航线仅用于视觉效果，不代表真实海上导航路径。

## 发布机制

仅 `release/v1.11.0` 分支的 Flutter/原生编译、Android 长期签名及证书指纹、Windows/Android SHA-256 和 ZIP/APK 校验全部通过后，GitHub Actions 才发布 `v1.11.0` 正式版，并保留历史版本与安装包。
