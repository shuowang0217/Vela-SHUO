# Official Mihomo core (Experimental Windows preview)

This branch adds the **unmodified official** MetaCubeX/mihomo Windows AMD64-compatible executable as a separate optional core next to the previously verified sing-box binary. Mihomo is NOT used by the default home connect button or Windows system proxy manager.

- Project: https://github.com/MetaCubeX/mihomo
- Source release: https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.32
- Asset: `mihomo-windows-amd64-compatible-v1.19.32.zip`
- SHA-256 (official GitHub release asset digest): `974a4d7ad69aed27aa2e8f91d61113573c14dadb14562c63e58effabf59816f0`
- Full original license is bundled as `core/LICENSE-mihomo.txt`.
- sing-box remains bundled with its existing official license and hash pin.

Mihomo project and contributors are not affiliated with Vela-SHUO. Experimental interface/translation code is Vela-SHUO-specific. No official Mihomo code is patched.

The Mihomo Lab binds only 127.0.0.1 on ports 20818/20819 and uses a random local API secret. It does not automatically set Windows system proxy. The test configuration includes node credentials and is cleaned up on normal stop/next launch; forcible OS termination can leave a local file until the next launch.
