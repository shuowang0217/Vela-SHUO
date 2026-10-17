# Vela 1.5.2 — Windows tray, navigation and airport names

Built on the user-verified 1.5.1 APK and portable Windows build, without
modifying that earlier artifact. Product name remains **Vela**.

## Changes

1. **Windows tray:** the off icon is truly grayscale; when the native
   WinINet proxy and Mihomo listener are both active, the same sail icon is
   colored. Tooltip is exactly `Vela` in both states. The tray context menu
   retains separate connection status and safe connect/disconnect actions.
2. **Navigation:** the four bottom dock buttons act as toggles. Clicking an
   already selected functional page returns to Home; selecting another page
   enters that page. The existing Home shortcut continues to work.
3. **Airport naming:** manual name wins. For a blank field, use the
   `Content-Disposition` filename from the **final HTTP 200 response**, as
   FlClash does. This works for connected stage-only imports and inactive
   direct imports. Invalid/absent filename metadata falls back to a numbered
   local airport label rather than exposing subscription URL tokens.

## Upgrade and validation

Android package: `com.shuowang.vela`, versionName **1.5.2**, versionCode
**25**, retaining the same pinned permanent signing certificate as 1.5.0
and 1.5.1. On Windows the executable remains `Vela.exe`; existing
per-user storage directories are unchanged.

The feature branch produces test APK and ZIP artifacts. Production Release
publication is restricted to `release/v1.5.2` after native tests and real
Windows tray verification. Check a 1.5.1→1.5.2 in-place Android upgrade
before any wider rollout.
