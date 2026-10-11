# Secure subscription snapshots

Starting in this version, Windows and Android offer an **explicit** “加密保存本机” button.

- There is **no silent default persistence**. The HTTPS subscription URL (frequently carrying bearer credentials) is never passed to persistent storage.
- The downloaded or pasted subscription **body does contain node credentials**. After opt-in only, it is stored in a versioned JSON snapshot using `flutter_secure_storage` (Android Keystore / Windows Credential Manager-based encryption). Do not confuse this with anonymized metadata.
- On launch, Vela attempts to restore the encrypted snapshot, re-parses it using exactly the same allowlisted parser and optionally re-selects a node. It never automatically enables Windows system proxy, starts Android VPN, or downloads subscriptions. Native Android VPN needs explicit consent and a home-screen button press.
- “删除本机存档” deletes only Vela's own encrypted snapshot. The currently loaded nodes remain until app exit. Changing a node or importing a new subscription does **not** silently overwrite the saved snapshot: click Update again.
- Restoration fails closed and displays a generic error, never raw credentials.
- On Android, auto-backup is disabled for the generated preview manifest to avoid restoring encrypted blobs without Android Keystore keys. The preview build is not a production-signed VPN release.
- Windows still generates a Mihomo runtime JSON profile in its existing application-managed config directory when a node is selected; that legacy runtime file contains credentials and is **not yet encrypted at rest**. Full runtime-profile minimization and cleanup is a separate release hardening task.
- A device already compromised by malware or an unlocked hostile account is outside the secure-vault guarantee.

Automated tests use a deterministic in-memory fake Vault. Release pipelines also compile both Windows native and Android ARM64 builds with the real plugin.
