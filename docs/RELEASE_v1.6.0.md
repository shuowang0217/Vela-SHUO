# Vela v1.6.0 正式版

基于已由用户实际安装、测试通过的 **Vela v1.5.3** 定版。保持原生 FlClash/Mihomo
业务核心及现有配置数据路径，不更换 Android 证书或应用 ID。

## Android ARM64 / Windows x64

- 手机代理节点采用自适应双列，更方便查看大量线路。
- Android VPN 通知仅在连接时出现，断开后自动消失。
- 延迟测速和下载测速独立成两个按钮：原生 URLTest 缩短失败等待，
  下载测速按原生单任务协议执行。
- Windows 和 Android 的连接卡片显示真实连接时长。
- 海上地图航线使用平滑曲线，减少突兀折角。
- 程序名称统一为 **Vela**，关于页面显示版本号。
- Windows 托盘：未启用代理是灰色图标，启用后显示彩色图标；
  鼠标悬停只显示 `Vela`。
- 四个功能按钮再次点击当前页时可返回主界面。
- 订阅名称留空优先使用机场 HTTP 响应给出的原始名称，
  手动填写名称时始终以手动名称为准。
- 连接状态显示 **未起航 / 正在起航 / 机场名称 · 抵达港口**，
  具体节点和连接时长仍保留。“抵达港口”是界面航海主题描述，
  并非经过验证的实际物理港口位置。

## 正式版身份和升级

- Android 应用 ID：`com.shuowang.vela`。
- Android versionName：`1.6.0`，versionCode：`27`。
- Android APK 使用自 v1.5.0 起固定的 `shuo-release` 正式签名，
  CI 严格检查证书 SHA-256 指纹
  `3e8826e8aa48576ddfce7a9a2e78106a159c7be05dbb3b2f89eb60fb095ac9d9`。
  1.5.0 / 1.5.1 / 1.5.2 / 1.5.3 可在签名和设备兼容时覆盖升级。
- Windows 可执行文件继续命名为 `Vela.exe`，原有用户配置目录不变。
  从便携版更新需要先在托盘选择安全退出，完整替换程序目录。

## 更新入口

软件内 **设置 → 检查更新** 会从此仓库的 GitHub
`releases/latest` 接口获取正式版本和对应平台安装包下载地址。
它不会静默安装：Android 仍需用户确认 APK 安装，Windows
下载后需用户自行退出旧程序并解压替换。

## 发布者身份提示

Android 正式签名保证的是 APK 同一开发密钥的完整性与升级兼容，
不保证第三方侧载安装没有系统“未知开发者”或 Play Protect 提示。
Windows 如果未提供受信任代码签名证书，Windows 仍可能显示
**未知发布者**。CI 支持使用独立配置的
`VELA_WINDOWS_CODESIGN_PFX_B64` 和 `VELA_WINDOWS_CODESIGN_PASSWORD`
对 Windows EXE 进行验证式 Authenticode 签名，缺失时如实发布未签名包；
不会生成自签名证书伪装真实发布者。

## 校验

只有 Flutter 静态检查和全部回归测试、Windows x64、Android ARM64
原生编译、Android 固定签名、包名/版本检查和两个安装包 SHA-256
校验全部通过，才自动发布 `v1.6.0` GitHub Release。
发布资产包括两个安装包和各自的 SHA-256 校验文件。
