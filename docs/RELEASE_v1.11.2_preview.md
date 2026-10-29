# Vela v1.11.2-beta.1+65 网络稳定性测试版

基于 v1.11.1+64；本版本仅提供 Windows x64 / Android ARM64 测试构建，不是正式 GitHub Release。

- 自动路由：连接时每 15 秒在本地通过 Mihomo getProxies 查询 URLTest/Fallback 的当前选择成员。只有选择链变化时才重新查出口 IP，正常仍每 2 分钟检查公网 IP。
- 网络恢复：离开前台超过 45 秒返回才进行路由及出口复检，短时间切窗口不重复检测；超过 6 分钟的缓存立即失效。不会自动打开 VPN 或系统代理。
- 分层诊断：设置页手动检查系统 DNS 与经过 Mihomo 的 HTTPS 两条链路，显示独立状态。系统 DNS 不等于代理 DNS。
- 界面不变：继续保留油画国旗、航海地图、连接状态及 Android VPN。
- 版本：1.11.2-beta.1+65，Android 包名 com.shuowang.vela，使用原长期签名；不覆盖正式 Release v1.11.0。

说明：自动分组选择仅代表当前组的链路，不等于规则模式对所有目标域名的路由。DNS 使用系统解析，不能证明 Mihomo 内置 DNS 的最终结果。
