# Vela-SHUO bundled independent proxy core

Vela-SHUO distributes an **unmodified, independent sing-box executable**
in a separate `core/` directory in its Windows ZIP. sing-box is NOT developed
by Vela-SHUO and is NOT affiliated with or endorsed by SagerNet.

- Project: https://github.com/SagerNet/sing-box
- Author: nekohasekai and contributors
- Exact version packaged: **1.14.3** (Windows amd64, stable, not alpha).
- Original release:
  https://github.com/SagerNet/sing-box/releases/tag/v1.14.3
- Exact upstream source corresponding to the binary:
  https://github.com/SagerNet/sing-box/tree/v1.14.3
- Official binary asset:
  https://github.com/SagerNet/sing-box/releases/download/v1.14.3/sing-box-1.14.3-windows-amd64.zip
- SHA-256 of that upstream archive (pinned and validated by CI):
  `d8b86ef58936dba9230ec6a57ffa4243933f3c14ef4809828b6c553440ed1518`
- License: **GNU General Public License v3 or later**, including additional
  upstream name/association notice as written in the upstream LICENSE.
- The ZIP includes `core/LICENSE-sing-box.txt` and
  `core/GPL-3.0.txt`, along with this notice. Please review these
  independently of Vela-SHUO's own source and license.
- The supplied binary is used as a separately launched process over local
  command-line and proxy interfaces, not as a linked library.
- No modifications to the upstream sing-box binary are made by Vela-SHUO.
- Updates to sing-box are not automatic. Users should only run verified,
  compatible versions and valid user-supplied subscriptions or servers.

A local generated configuration containing only a `direct` outbound is
created for first-run diagnostics. It **does not provide a foreign proxy,
subscription, VPN, or access to blocked remote networks**. It does not
intercept operating-system traffic. Vela-SHUO also does not modify existing
Windows proxy settings in this version.

This file is a distribution notice, not a substitute for the full upstream
GPL license text packaged inside `core/`.
