# Vela 1.9.0+57：油画帆船「扬帆」

## 三星 One UI 图标长按菜单
- 只有一个动态应用快捷入口，原版深蓝金色油画帆船图标，名称固定「扬帆」。
- 连接状态不再更改快捷入口名称，避免已打开的长按小窗显示旧名称。
- 点击根据 VpnService 的真实连接状态自动切换：
  - 未连接：发起启航，弹出短 Toast「正在启航…」；
  - 已连接：发起返航，弹出短 Toast「正在返航…」；
  - 正在连接：提示「正在启航，请稍候」，不重复启动。
- 点击仅启动透明原生 Android Activity，不打开 Flutter 主界面。
  首次或 VPN 权限失效时，仍需 Android 系统 VPN 授权。
- 这些 Toast 表示已发送操作指令，不是假定真实 VPN 已连接或断开。
- 动态快捷菜单名称只需在首次升级时替换，后续状态切换无需强制 One UI 菜单重绘。

## 安装与兼容
- App ID 继续是 com.shuowang.vela，沿用此前稳定 Android 签名。
- versionCode 57，可覆盖原 53 / 54 / 55 / 56 版，保留机场配置。
- 首次安装后正常打开 Vela 一次，完成扬帆快捷项注册与当前节点缓存。
- 之前手动固定的旧快捷图标，必要时自行从桌面移除。
- 不新增任何 AppWidget；保留 FlClash/Mihomo 真实 VPN 内核和原有 Vela UI。

本次快捷图标直接复用 `scripts/prepare_selected_brand.py` 从 Vela 已选定油画品牌原画中生成的 `assets/brand/vela_selected_icon.png`；未更改启航/返航及原生 Toast 逻辑。
