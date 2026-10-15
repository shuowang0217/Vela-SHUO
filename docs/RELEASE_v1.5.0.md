# Vela 1.5.0 — stable release

Official product name: **Vela** (Windows and Android).

This release promotes the user-tested Android/Windows build #358 with
FlClash/Mihomo native routing, native policy groups, Android foreground
traffic notification and the Vela interface. Version is `1.5.0+23`.

## Durable upgrade identity

- Android stable package: `com.shuowang.vela`, starting at versionCode 23.
- Android stable signing **must** use one retained private release key from
  GitHub Actions secrets. Never publish with ephemeral Android Debug signing.
- Future APK versions must keep the same package ID and signing certificate
  and increase versionCode. Installing the newer APK then preserves app data.
- **Migration limitation:** v1.4.7 beta `com.shuowang.vela.vpn.beta`
  used ephemeral debug signatures (two verified builds had different
  certificates). In-place migration is therefore not guaranteed. Vela 1.5.0
  uses a new stable package ID; users should keep the old app temporarily,
  export/copy their subscription YAML or URLs securely, install 1.5.0,
  reimport and verify it, then uninstall the beta. Android's encrypted app
  storage cannot automatically be migrated between these package IDs.
- Windows program and title: `Vela.exe` / `Vela`; previous Windows
  per-user storage path stays `Vela-SHUO/FlClash-Core` to preserve profiles.
  Shut down before replacing the entire portable program folder.
- Settings → 检查更新 queries only GitHub's latest verified stable release.
  Users approve opening the official package link; this is **not** silent
  installation and does not bypass Android installation prompts.

## Mandatory signing setup before publishing

Configure these repository **Actions secrets** (never in source, artifacts,
logs or chat): `VELA_ANDROID_KEYSTORE_B64`,
`VELA_ANDROID_STORE_PASSWORD`, `VELA_ANDROID_KEY_ALIAS`,
`VELA_ANDROID_KEY_PASSWORD`, `VELA_ANDROID_CERT_SHA256`.

Generate one durable keystore using a trusted local machine:

```sh
keytool -genkeypair -v -keystore vela-release.jks -alias vela \
  -keyalg RSA -keysize 3072 -validity 10000
base64 -w0 vela-release.jks > vela-release.jks.b64   # GNU/Linux
keytool -list -v -keystore vela-release.jks -alias vela
```

Use the Base64 file contents as `VELA_ANDROID_KEYSTORE_B64`.
Set SHA-256 fingerprint without spaces or colons (lowercase) for
`VELA_ANDROID_CERT_SHA256`. The alias/password secrets must match the key.
Store a secure offline backup of the original `.jks` and passwords.
**Losing the key makes future in-place APK updates impossible.**

The release workflow refuses to build the Android stable APK without all
five secrets and checks that the signed APK's certificate matches the
pinned fingerprint. Only after UI tests, Android and Windows builds, and
SHA-256 checks pass may the workflow publish GitHub Release `v1.5.0`.
The GitHub release contains durable APK/ZIP assets (not expiring Actions
artifacts).

## Release qualification

- Confirm Release v1.5.0 assets are published, not just CI success.
- Verify Android certificate and versionCode 23, and matching identity.
- Test Android VPN rule/global/direct on a real device and notification.
- Install a separately signed future test version with increased versionCode
  over v1.5.0 to validate profile preservation.
- On Windows verify Vela.exe launches and old per-user profiles are retained.
