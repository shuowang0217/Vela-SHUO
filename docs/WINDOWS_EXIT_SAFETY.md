# Windows 退出可靠性（2026-10-10）

本轮针对“关闭 Vela-SHUO 后后台 Mihomo 遗留、再次启动 20808 被占用”完成生命周期加固：

- 原先仅在 `AppLifecycleState.detached` 发起异步清理，窗口销毁时 Dart 进程可能已停止，无法保证恢复系统代理和结束 Mihomo。
- Windows 增加 `window_manager.setPreventClose(true)`，收到点击关闭后等待 `VelaConnectionCoordinator.shutdown()`。先阻止新连接，等待既有连接任务结束，再恢复 WinINet 快照，最后停止 Mihomo，成功才销毁窗口。
- 如果恢复系统代理失败，将保留窗口和代理内核（避免断网），向界面报告恢复失败并允许用户重试关闭。
- Windows native `Job Object` 启用 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`。Vela-SHUO 的 Mihomo 子进程绑定本进程持有的 Job handle。即使用户强杀主程序或它崩溃，OS 释放 handle 时将终止该子进程。**不**扫描 `mihomo.exe` 名称或杀掉 FlClash 等别的客户端。
- 强杀程序时 WinINet 无法实时恢复；下次正常启动会依据既有 `proxy-recovery.json` 日志尝试恢复，绝不覆盖第三方后来设置的代理。
- 旧版已遗留的、没有新 Job Object 保护的 Mihomo **不会自动杀掉**，需要用户确认路径后手动结束。Windows Job API 不可用时拒绝启动不受托管的内核。

CI 需要 Flutter 静态分析、单元测试、Windows Release 编译、Mihomo 官方 SHA-256 及内核配置自检均通过。Windows 实机进一步验证：已连接状态点击关闭、连接中关闭、任务管理器强杀、重启恢复、多个客户端共存、Windows PAC 和其他工具修改代理场景。
