# Vela-SHUO

**Original network client by SHUO.** This is a brand-new Flutter application, not a fork of FlClash.

## v0.1-A: independent cloud-buildable foundation
- Original responsive Chinese interface: Overview, Nodes, Smart, Settings.
- Light / dark / system appearance persisted locally.
- Deliberately no proxy engine, VPN permission, subscriptions, or fabricated network data yet.
- GitHub Actions builds a Windows **portable ZIP containing Vela-SHUO.exe plus its required runtime files**, and an Android ARM64 **debug DEV APK**.

## Product identity
- Product name: **Vela-SHUO**
- Flutter package: `vela_shuo`
- Windows EXE: `Vela-SHUO.exe`
- Android production ID reserved for future stable release: `com.shuowang.vela`
- Current Android DEV install ID: `com.shuowang.vela.dev`
- Version: `0.1.0+1`

## Build / installation
No local SDK required. Open this repository's **Actions** tab, select **Vela-SHUO CI**, open a successful workflow run, and download the Windows or Android artifacts. Extract the entire Windows portable ZIP before starting the EXE.

Android alpha builds use the ephemeral debug signing key generated on the GitHub runner. Different build runs may use different debug certificates, so Android may require uninstalling the previous **DEV** version before installing the next test package. Do not put personal configurations in this test build. Permanent release signing will be added in v0.1-D without sharing keys with FlClash-Custom.

The project does not yet provide actual proxy connectivity; that is scheduled for v0.2. Keep the existing stable FlClash-Custom installation untouched.

See [roadmap](docs/ROADMAP.md). This is a private prototype; any later third-party network core must be reviewed for licensing and security.
