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

## Permanent signing (reuse existing FlClash-Custom key)

Vela 1.5.0 **reuses the existing fixed FlClash-Custom certificate**, not a
new key and not Flutter's ephemeral debug signer.

- Source: `shuowang0217/FlClash-Custom` pinned revision
  `086d91b619538809d4b0aa86b57c7dc85e9d16ce`.
- Encrypted key: `android/signing/shuo-release.jks.enc` (safe ciphertext;
  never commit the decrypted `.jks`).
- Restore program: `scripts/shuo_signing.py restore`.
- Alias: `shuo-release`.
- Pinned **public certificate SHA-256**:
  `3e8826e8aa48576ddfce7a9a2e78106a159c7be05dbb3b2f89eb60fb095ac9d9`.

**One secret is required in the Vela-SHUO repository:**
`SHUO_SIGNING_PASSWORD` with exactly the **same saved password value** as
the original secret in FlClash-Custom. GitHub Actions secrets are scoped per
repository, so they are not automatically shared. GitHub does not allow
reading a stored secret value; retrieve it from the original password manager
or secure offline backup. Do **not** paste it into chats, issue comments,
source code, or workflow inputs.

In `Vela-SHUO → Settings → Secrets and variables → Actions → New repository secret`,
create `SHUO_SIGNING_PASSWORD`. When it is configured, rerun the release
build. CI decrypts the immutable ciphertext on the temporary runner, signs
the APK under the stable Vela package ID, verifies the certificate digest
against the pinned public fingerprint, and removes plaintext private keys.
A missing secret or mismatch **fails the release**; no unsigned fallback.

The signing certificate can be used by two **different application IDs**
(`com.shuowang.flclash.custom` and `com.shuowang.vela`) without making
them install over each other. Existing Vela beta data still requires
one-time migration as described above. Future Vela updates must keep
`com.shuowang.vela`, the pinned signing certificate, and an increased
Android `versionCode`.

Only after UI tests, Android and Windows builds, checksum and signer checks
pass may CI publish durable GitHub Release `v1.5.0` assets.


## Release qualification

- Confirm Release v1.5.0 assets are published, not just CI success.
- Verify Android certificate and versionCode 23, and matching identity.
- Test Android VPN rule/global/direct on a real device and notification.
- Install a separately signed future test version with increased versionCode
  over v1.5.0 to validate profile preservation.
- On Windows verify Vela.exe launches and old per-user profiles are retained.
