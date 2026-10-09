# Vela-SHUO

**全新原创的 Windows / Android 网络工具。** 独立于 FlClash-Custom，不包含任何旧项目源代码。

## 当前阶段：v0.1-B 原创首页 UI

首页按已确认的视觉稿重新设计：

- 冷调深海蓝、冰蓝发光、简笔帆船和玻璃质感卡片。
- 独立原创的正交球面投影地球，使用真实世界地理轮廓（而非拼贴圆块）；未连接时以中国大陆为中心。
- 演示连接后转向日本、美国、新加坡、英国或德国节点，并绘制从中国到目标国家的地理航线。
- Windows 侧边导航与 Android 底部导航；适应不同屏幕。
- 节点页可选择**演示节点**，智能页可操作**演示开关**。
- 深色主题默认开启，仍可切换浅色或跟随系统，主题本地持久化。

**重要：这是 UI 原型，不具备真实代理/VPN/测速能力，所有节点及指标为明确标注的演示数据。** 真实连接将通过后续 v0.2 的独立内核适配实现。

### 云端构建

**Windows-first 阶段（用户于 2026-10-09 确认）**：GitHub Actions 只运行 Flutter 静态检查、测试和 Windows x64 构建，输出完整便携版 ZIP（内含 Vela-SHUO.exe 与所需 DLL/数据文件）。不再为每次提交自动构建 Android。所有构建工具均在 GitHub 云端运行，无须本地安装。

**Android 暂停开发与构建**，直到 Windows EXE 完成正式版验收。届时基于同一套 Dart/Flutter 界面进行 Android 适配和实机验证，再生成正式签名 APK。Android 预留包名：com.shuowang.vela（DEV 后缀 .dev）。历史测试 APK 不视为 Android 正式版。

### 地图地理数据

球体采用 Natural Earth 公开地理边界资料，由 https://github.com/holtzy/D3-graph-gallery/blob/master/DATA/world.geojson 的示例数据提取和简化。Natural Earth public-domain 地图数据；地图绘制、渲染算法、航线、简笔帆船及界面均在本项目中实现。

开发计划见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 安全

- 不会建立网络代理连接。
- 不会申请 VPN 权限或运行后台代理。
- 不会生成虚假的“真实测速”或“真实连接成功”通知。
- 不修改已有的 FlClash-Custom 仓库或安装身份。

### 近期发布策略

1. 只迭代 Windows UI、交互、稳定性和网络功能，提供 Windows EXE 测试构建。
2. 完成 Windows 真实连接、异常恢复及实机验收后，再发布 Windows 正式版。
3. Windows 正式版确认后，恢复 Android 专项工作流，完成 VPN 服务适配、持久化正式签名与真机测试后再发布 APK。
4. 此前成功构建过 Android DEV APK，但不再随代码改动重复构建。不要把 UI 原型版误认为完整代理功能。
