# Vela v1.7.0 正式版

最终定版源于已通过双平台构建与测试的 v1.7.4 开发分支。
正式版本为 **1.7.0+33**，Android versionCode **33**。

## 改进及兼容性

- 六朵自然、不规则的手绘水彩云在地图上方缓慢漂移，
  使用独立 Flutter Canvas 层，无需旧 GPU 气象 Shader。
- 北京（BEIJING）作为起点，连接后仅显示起点与真实节点
  目的城市的英文手绘地图标签；断开时只显示 CHINA。
- 保留顶部半透明毛玻璃通知、原生 FlClash/Mihomo 网络核心、
  订阅和已有连接功能。
- 下载测速完全沿用 v1.6.0 验证过的原版实现。
- 合并定版历史至 main，同时保留之前的 Release 标签、发布包和历史分支。

## 安装和升级

Windows x64：`Vela-v1.7.0-Windows-x64.zip`，完整退出旧版后解压。
Android ARM64：`Vela-v1.7.0-Android-arm64.apk`，固定包名
`com.shuowang.vela` 和原有正式签名。

Android versionCode 33 高于之前 v1.7.4 开发版的 32，
因此能够在签名一致的情况下覆盖升级。但如果从显示版本号
较高的测试版改装 v1.7.0，应用内的语义版本更新检测可能
不会主动提示，请手动下载安装。

此版经过 Flutter/UI 测试、Windows/Android 双平台构建、
Android 签名身份和 SHA-256 验证后才允许发布。
