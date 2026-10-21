# Vela 1.9.0+54 Android 图标快捷操作预览

本版本从稳定版 main 直接分支，不再包含之前测试版的 AppWidget 桌面小组件。

在三星 One UI 主屏幕长按 Vela 图标：
- 启航：打开 Vela，恢复机场，验证规则设置，再发起 Android VPN 连接；
  首次连接的 Android 系统 VPN 权限弹窗不会被绕过。
- 停止航行：打开 Vela，通过原生 VPN 控制器断开当前连接。
- 部分 Samsung One UI 版本可从长按菜单拖动快捷项到桌面，是否支持以启动器为准。

同包名 com.shuowang.vela 和相同长期签名；预览内部码 versionCode 54，
高于旧小组件安装包的 53，可覆盖安装并保留机场数据。
不修改现有 FlClash/Mihomo 内核。正式版 v1.9.0 Release 不受影响。

如旧小组件图块未被启动器自动删除，长按旧小组件并手动移除。
