# Vela 1.9.0+55 · 三星 One UI 动态油画罗盘快捷操作

从 Vela 1.9.0+54 快捷菜单测试版升级。保留原应用包名、正式签名、
现有机场配置和 Mihomo/FlClash 网络核心。无桌面小组件。

- Vela 图标长按菜单只有一个动态快捷操作，其图标采用原版油画导航罗盘。
- 未连接：`启航`；已建立真实 VPN TUN：`返航`。
- 使用 Android ShortcutManager 的稳定 ID `vela_compass_toggle`
  替换和更新唯一动态快捷操作；不注册旧静态「启航 / 停止航行」双入口。
- 点击快捷操作只打开透明原生 Activity（没有 Flutter/Vela 主界面）。
  已授权情况下由此直接启动/停止真实 Android VpnService；
  Android 需要 VPN 授权时只显示系统授权界面。
- 连接读取已缓存的 selectedMap/route-mode 和本机 FlClash-Core/config.yaml，
  不虚构节点/凭据。只有在 Vela 正常启动并加载过有效机场后，
  后台快捷启航才具备必要配置；无配置时只提示需先导入。
- VPN 状态以 VpnService.report 为准，网络未真正连接不显示返航；
  系统启动器接收动态图标文字更新可能存在短暂延迟/速率限制。
- 安装包版本 1.9.0+55，versionCode 55，可覆盖 53/54 且保留数据。
- 测试版 GitHub Actions 构建；正式 1.9.0 Release 不改变。

注意：安装新版本后需正常打开 Vela 一次完成动态快捷菜单注册和机场选择缓存。
此前若已把旧双入口快捷项固定到桌面，请手动删除旧快捷项。
