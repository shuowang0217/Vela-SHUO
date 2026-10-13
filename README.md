# Vela-SHUO

**当前正式版本：v1.0.0**

Vela 是基于 Flutter 的 Windows / Android 代理客户端，保留 Vela 原创界面，
底层使用 [FLCLASH-CUSTOM](https://github.com/shuowang0217/FlClash-Custom) 的原生 FlClash / Mihomo 网络核心。

## v1.0.0：项目正式起点

2026-10-13 确定 `v1.0.0` 为项目首个正式稳定基线，不再以早期实验版、
旧版 `main` 架构或临时构建作为后续开发基础。

- **已验证的功能基线提交**：`b60f3b7a349565d6b1ec83b4bd2464b6f23a2257`
- **正式开发主线**：`main`
- **v1.0.0 版本分支**：`release/v1.0.0`
- **软件版本号**：`1.0.0+1`（见 `pubspec.yaml`）
- **构建流程**：`.github/workflows/vela-host-flclash-core.yml`

v1.0.0 功能范围：

- Windows x64 和 Android ARM64，采用 Vela 原版 UI。
- 使用 FLCLASH-CUSTOM 的原生 FlClash Go / Mihomo 核心。
- 导入订阅、节点搜索、收藏、节点选择和连接状态显示。
- 全节点延迟测试及真实下载测速：批量延迟、逐个下载；节点卡片同时显示延迟与下载 MB/s。
- 分别记录测速成功、失败及可安全展示的失败类别。
- Windows 点击窗口关闭（×）默认最小化到任务栏，运行中的代理保持连接。
  在「设置 → 安全退出」才断开代理并恢复 Windows 系统代理设置。
- Android 使用原生 VPN / TUN，已接入延迟与下载测速功能。

## 下载与运行

前往仓库 [Actions](https://github.com/shuowang0217/Vela-SHUO/actions)
选择 **Vela v1.0.0 - Windows and Android (FlClash core)** 构建，
在 Artifacts 中下载：

- Windows x64 便携包：完整解压，运行 `Vela-SHUO.exe`，不要单独移动 EXE。
- Android ARM64：安装构建产物中的 APK。升级前请自行备份订阅和设置。

## 后续版本约定

从 v1.0.0 开始迭代，每次修改以此稳定版为基础，正常升级版本号
（例如 v1.0.1、v1.1.0）。以前的实验分支和旧构建不作为正式发布版本。
Git 历史可保留用于技术追溯，不代表这些旧版本受支持。

## 注意

CI 构建及自动化测试不能替代所有网络与设备环境下的实机验证。
测速结果取决于代理线路与测试服务器可达性。
使用第三方内核时应遵循相应开源许可。
