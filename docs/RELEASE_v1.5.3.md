# Vela 1.5.3 — 航行状态与发布者身份

以已验证的 Vela 1.5.2 为基础。本分支仅作为测试构建，不覆盖旧版 Release。

## 界面

- Windows、Android 连接卡片：断开显示 **未起航**，连接中显示 **正在起航**。
- 真实连接成功后显示 **机场名称 · 抵达港口**，仍显示连接时长和选中节点。
  “抵达港口”是软件航海主题文案，不代表已测得网络出口的真实城市/港口。
- 未命名机场显示 **Vela · 抵达港口**，不会泄露订阅 URL。

## Windows 未知发布者 / SmartScreen

当前测试版 `Vela.exe` 未配置受信任 Windows Authenticode 证书，
仅有产品信息和 Vela 图标不足以建立 Windows 发布者身份。

CI 已加入**可选**的发布者签名流程，需在 Vela-SHUO 仓库的
Repository Actions Secrets 配置以下两项：

- `VELA_WINDOWS_CODESIGN_PFX_B64`：受信任代码签名证书 PFX 的 Base64
- `VELA_WINDOWS_CODESIGN_PASSWORD`：该 PFX 的密码

完整证书必须有 Code Signing 许可并属于已验证的合法发布者，不能使用
自签证书冒充受信任发布者。证书内容和密码禁止写入仓库或聊天。
CI 仅在同时存在两项时签名并校验 `Vela.exe`、
`core/FlClashCore.exe`、`core/mihomo.exe`，签名必须通过受信任链校验，
随后才可打 ZIP。不配置则仍可构建**未签名测试包**。

即使已签名，微软 SmartScreen 仍可能在声誉建立之前弹窗。
非商店发行可以考虑 Microsoft Artifact Signing；商店发布也是选择。

## Android 未知开发者 / 来源警告

现有正式密钥已经固定用于 com.shuowang.vela，1.5.3 的
`versionCode=26`，保持 1.5.2→1.5.3 安装包签名一致。
这只解决覆盖升级，不等于 Google 或设备制造商的开发者实名验证。

在 Google Play 发布需要完成 Play Console 开发者登记及相关 VPN
政策要求。若采用应用商店外分发，可在 Android Developer Console
完成开发者身份验证和应用登记，以满足对应地区的新要求；
仍无法保证完全消除“允许此来源安装应用”或 Play Protect 提示。
不要通过更换现有 Android keystore 解决信任提示，否则会破坏覆盖升级。

## 分发

开发分支 `feature/v1.5.3-voyage-status-publisher-identity` 仅产出 CI
测试包；正式 Release 限制为 `release/v1.5.3`。
