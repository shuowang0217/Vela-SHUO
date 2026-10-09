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

GitHub Actions 会自动验证源码并尝试生成 Windows x64 **完整便携版 ZIP**（内含 Vela-SHUO.exe 和运行所需 DLL/数据文件）及 Android ARM64 **DEV APK**。Flutter / Android SDK / Windows C++ 工具链都由云端提供，无须本地安装。

Android 测试包名：com.shuowang.vela.dev。此阶段采用 CI 运行器临时调试签名，**不同构建之间可能无法覆盖安装**；不要在测试版中保存重要配置。正式签名与 EXE 安装程序计划在 v0.1-D 实现。

### 地图地理数据

球体采用 Natural Earth 公开地理边界资料，由 https://github.com/holtzy/D3-graph-gallery/blob/master/DATA/world.geojson 的示例数据提取和简化。Natural Earth public-domain 地图数据；地图绘制、渲染算法、航线、简笔帆船及界面均在本项目中实现。

开发计划见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 安全

- 不会建立网络代理连接。
- 不会申请 VPN 权限或运行后台代理。
- 不会生成虚假的“真实测速”或“真实连接成功”通知。
- 不修改已有的 FlClash-Custom 仓库或安装身份。
