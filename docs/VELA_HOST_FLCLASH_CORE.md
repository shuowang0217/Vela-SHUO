# 正确的整合方式：Vela-SHUO 主程序 + FlClash 后台

## 不能改变的部分

以本仓库 `main` 分支原版 Vela-SHUO 为主工程。原始 `lib/main.dart`,
`lib/src/app.dart`, `lib/src/home/`, `lib/src/smart/`,
`lib/src/subscription/`, `lib/src/settings/`, `assets/` 保留其外观、
布局、导航、动画、配色和交互约定。

**绝对不使用 FlClash 的 Flutter 首页、设置页、导航或窗口外壳。**
禁止再使用 `prepare_flclash.py` 向 FlClash 覆盖 Vela 部件的反向移植方式。

## FlClash 负责不可见的网络功能

上游代码固定到
[chen08209/FlClash@4b59eca](https://github.com/chen08209/FlClash/tree/4b59eca853778d4e7be3de26589252889c899bc5)
及其 `core/Clash.Meta` 子模块 `8597778c7df410ebe88c57e59eaab32d203156df`。

- **Windows**：从上游 FlClash 使用的 `core/Clash.Meta` Go 源码编译
  `mihomo.exe`，放入原版 Vela 程序已有的
  `core/mihomo.exe` 路径。界面仍由 Vela 自己构建和绘制。
- **Android**：从上游 FlClash Go `core` 源码构建
  `libclash.so`，并从 `android/core` 复制原生 JNI 封装，
  生成 `libcore.so`。Vela 自己的 Android VPN 服务经
  `scripts/migration/attach_flclash_android_core.py` 接入
  `com.follow.clash.core.Core`，不再调用旧的
  `io.github.oviron.libmihomo.Clash` AAR。
- **界面 UI**：始终由本仓库原始 `VelaShuoApp` 渲染，不用 FlClash
  `Application` 或 `HomePage`。

## 现阶段的边界（必须诚实标注）

这还不是完整的最终产品，且尚未验证 Windows、Android 两个平台实机：
1. Windows 的 Mihomo 数据面来自 FlClash 锁定的源码；Vela 的
   配置转换、订阅管理、智能优选及应用级控制器目前仍是原 Vela
   实现。下一步要逐步适配 FlClash 的 Go 控制 API。
2. Android 的 JNI/TUN 适配已经写入迁移构建脚本，但必须经编译与
   Android 实机 VPN 权限、路由、DNS、断开恢复验证。
3. 不能把一次 CI 的编译通过当作 VPN 的实际功能证明。
4. 原版 Vela 的业务页面可能仍显示原有状态文案；在接入真实 FlClash
   后台前不应以伪造数据代表实际速度和连接。
5. 开源分发必须保留上游 GPL 与其他依赖的版权许可证。

## 迁移准则

1. 主工程：`Vela-SHUO` 的 Flutter 代码和窗口样式。
2. 网络引擎：从锁定的 FlClash / Mihomo 上游源码构建。
3. 适配层：位于 `native/`, `scripts/migration/` 与专用
   `lib/src/core/` 桥接代码，不能反向改写 Vela 的 UI。
4. CI 必须检查 Vela UI 原样构建、上游源码 SHA、两端引擎产物；
   实机功能另行验收。
5. 不触动 `main`，所有工作在 `migration/vela-host-flclash-core`。
