# Vela

**正式版 1.9.0**（Android build 53） · Windows x64 / Android ARM64

原创航海油画风格网络客户端，原生 FlClash / Mihomo 内核处理协议、分组、规则与 DNS。源码仓库继续使用 `Vela-SHUO` 作为内部名称。

## 正式版下载

[GitHub Releases · 最新 Vela](https://github.com/shuowang0217/Vela-SHUO/releases/latest)

- **Android**：`Vela-v1.9.0-Android-arm64.apk`。固定包名 `com.shuowang.vela`，沿用原正式签名，versionCode=53。同签名旧版可覆盖安装，原配置和偏好通常能够保留。
- **Windows**：`Vela-v1.9.0-Windows-x64.zip`。使用「安全退出」关闭旧版，完整解压后运行 `Vela.exe`，不要只复制 EXE。

应用「检查更新」读取 GitHub 最新正式 Release，不会在后台静默安装软件。

## 1.9.0 改进

- **机场列表**：正在使用的机场优先排列，轻微选中高亮。Windows 保留双列宽度，同排卡片等高；手机保持单列统一基础高度。
- **Windows 装饰航线**：兼容 CRLF 与 LF 海洋网格换行，恢复海上轨迹与航行小船显示。
- **Android 速度通知**：实际油画海景（海鸥、帆船、海面），独立显示风速和航速，不重复系统图标，遵守系统外壳显示限制。
- **代理模式**：规则、全局、直连切换使用 Android 原生持久化与读取确认；规则设置弹窗不再压暗地图。
- **机场订阅自动更新**：15 分钟起、应用**运行期间**定时检查，失败按间隔重试，回到前台时复查；退出软件后不保证后台自动更新。
- **延迟测速**：状态文案统一为 Vela，仍由原生 Mihomo 内核提供测量结果。

海图中的航线仅用于视觉效果，不代表真实海上导航路径。

## 发布机制

仅 `release/v1.9.0` 分支的双平台签名、构建、Flutter 测试、版本和 SHA-256 校验全部通过后发布 v1.9.0 正式版，保留此前各版本的历史安装包与 Release。
