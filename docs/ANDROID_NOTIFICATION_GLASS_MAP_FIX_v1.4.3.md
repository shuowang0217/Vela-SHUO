# Vela v1.4.3 修复版 · Android 通知与手机玻璃地图

以 v1.4.2 双端修复版为基线；不覆盖 v1.4.0 稳定版。
- 修复 JNI：原生 Kotlin 通知通过固定 FlClash 核心提供的 `Core.getTotalTraffic(false)` 读取计数；构建时由既有 FlClash Android 适配脚本替换 Java/Kotlin JNI 调用。
- 通知只保留矢量小帆船图标、上传与下载两项实时速率，**单行**显示；不带断开 VPN 操作、不增加悬浮窗权限。点击通知进入应用。
- Android 通知在 HTTPS 验证成功后每约 2 秒采样一次累计字节计数，按单调时钟计算实际字节/秒，VPN 断开立即终止轮询。
- Android 竖屏地图比例由 `2.08` 缩小为 `1.68`（按屏高转换为贴图世界宽度），露出更多世界区域；上下边缘用同地图的模糊填充和羽化过渡，不出现硬边/黑条。Windows 地图镜头尺度维持原状。
- Android 水彩浮动卡片统一 **50% 不透明 / 50% 透明**，保留 9～10px 背景模糊及原来墨线/水彩色。Windows 已验收的毛玻璃材质不变。
- CI 同时测试并构建 Windows x64 + Android ARM64；仅在 Android Kotlin 编译、Flutter 测试通过且 APK 实际生成时交付。
