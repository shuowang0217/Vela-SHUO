# Vela-SHUO v1.2.0 — 稳定版

发布日期：2026-10-14

## 版本基线

- 基于经过 Windows/Android CI 完整验证的 `feature/v1.0.0-earth-glass-plus` 提交 `901ccd8d6a31957801868ad68b33adeffb13698c`。
- 仅调整软件版本号、托盘与设置页的版本文案、正式构建文件名；**不修改网络内核和现有功能逻辑**。
- 版本号：`1.2.0+3`（Flutter/Android build number 3）。

## 定版功能

- 保留 v1.0.0 原始布局，以真实纹理的动态地球作为整个程序背景。
- 更高透光率的半透明毛玻璃组件，深浅色主题兼容。
- Windows 托盘：关闭按钮隐藏到托盘、最小化按钮正常最小化、托盘状态与代理操作、安全退出恢复系统代理。
- 本机多订阅存储（最多 20 份）：保存、恢复、更新、切换、重命名及删除；切换失败时尝试恢复先前线路。
- Windows 系统代理与 Android VPN 按原先支持能力使用 FlClash / Mihomo 网络内核。
- 保留原有的诊断、测速/优选以及界面回归测试。

## 验证和限制

上一版功能基线的 CI 已通过 Flutter 静态分析、单元/界面测试、Windows x64 与 Android ARM64 构建：
https://github.com/shuowang0217/Vela-SHUO/actions/runs/38505761899

本分支中版本号已更新，发布专用 CI 会重新生成带 v1.2.0 名称的构建产物。**只有该 CI 成功后才能将其称为 v1.2.0 构建通过**。

Windows 提供系统代理，而非 TUN 全局 VPN；Android VPN 的平台授权及支持范围保持原版。
当前仅通过 CI 构建和测试，尚不等同于在所有真实设备上验证运行。

## 安装

- Windows x64：下载 `Vela-v1.2.0-Windows-x64` 构建产物，取出完整 ZIP 后整体解压，启动 `Vela-SHUO.exe`。
- Android ARM64：下载 `Vela-v1.2.0-Android-arm64` 构建产物，安装其中的 APK。
- 请确认 `SHA256-Windows.txt` 或 `SHA256-Android.txt` 与下载文件对应。

## 后续修改规则

`release/v1.2.0` 视作冻结版本。后续新功能在单独的功能分支开发，不直接改变此定版。
