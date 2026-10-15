# Vela v1.4.0 · 正式版（Watercolor Unified）

**正式定版：2026-10-15**  
**用户验收基线：** `feature/v1.3.1-watercolor-unified`，提交 `cb1c9a940de6274553e4ec096a82ced3085cce41`。

此版本为用户确认的水彩世界地图与极简航海界面的正式稳定版本。从验收通过的构建到 v1.4.0，只更新版本信息、发行说明和 CI 安装包命名，不更改 UI、地图、动画或代理业务代码。

## 视觉与交互
- 水彩世界地图：昼景与地理对应的夜航地图（城市灯光）、无缝平铺、节点聚焦与帆船航线动画。
- 极简沉浸式首页：顶部一键连接/断开；左下角「风速 · 上传」和「航速 · 下载」，自适应 B/s、KB/s、MB/s、GB/s。
- 四个分离的悬浮航海图标入口：代理、机场配置、智能优选与系统设置；所有桌面页面统一水彩玻璃、细墨线和航海标识。
- Windows 点击连接时不再重复弹出系统代理确认框；连接仍保留 HTTPS 校验、系统代理备份/失败回滚和断开恢复。
- Android VPN 权限仍由 Android 操作系统授予。

## 真实代理功能
- Windows：FlClash Go + Mihomo 系统 HTTP 代理；不是整机 TUN VPN。
- Android ARM64：FlClash Go JNI + Android VPN Service。
- 多机场配置保存/切换、订阅更新、真实节点选择、规则/全局/直连分流、智能优选与流量统计保持不变。

## 安装与校验
- Windows x64：`Vela-v1.4.0-Windows-x64.zip`。解压后运行 `Vela-SHUO.exe`，保留同目录内全部核心及资源文件。
- Android ARM64：`Vela-v1.4.0-Android-arm64.apk`。
- 随附 `SHA256-Windows.txt` 和 `SHA256-Android.txt` 供独立校验。
- 自动 CI 在 Flutter 静态分析、测试、Windows 和 Android 构建全部成功并确认包校验和之后，才会发布正式 `v1.4.0` 标签与 GitHub Release。

## 版本冻结
`release/v1.4.0` 和 `v1.4.0` 为冻结版；后续功能在独立开发分支迭代，不回改已发布的版本。通过 CI 不等同于覆盖所有机器和网络环境的实际验收。
