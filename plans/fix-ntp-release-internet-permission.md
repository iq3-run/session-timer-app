# Fix: NTP sync always fails in release builds (missing INTERNET permission)

Issue: <https://github.com/iq3-run/session-timer-app/issues/59>

## Problem

NTP sync ("おまけ：時刻同期（NTP風）" in the settings sheet) fails with
「同期失敗（インターネット接続を確認してください）」.

Investigated on BlueStacks (127.0.0.1:5555, Android 9 / API 28):

- Network layer is fine: IPv4 ping to `ntp.nict.jp` succeeds, DNS resolves
  multiple IPv4 addresses. IPv6 has no route on this device
  (`Network is unreachable`), but the IPv4-preference fix from issue #42 /
  PR #43 already handles that.
- `flutter run --debug` deployed straight to BlueStacks → sync **succeeds**
  (誤差補正 -1205ms).
- `flutter build apk --release` installed on the same device/network → sync
  **always fails**.

## Root cause

`android/app/src/main/AndroidManifest.xml` never declares
`android.permission.INTERNET`. `android/app/src/debug/AndroidManifest.xml`
and `android/app/src/profile/AndroidManifest.xml` already declare it
themselves (for the Flutter tool's VM Service/DevTools connection), and
Gradle's manifest merger folds those in only for their respective build
variants — so debug/profile builds got `INTERNET` from those files, while
release, which only merges `src/main`, got none.

Confirmed via `aapt dump permissions` on both APKs built from the same
commit: the debug APK includes `android.permission.INTERNET`, the release
APK does not. Every other permission (`ACCESS_NETWORK_STATE`,
`POST_NOTIFICATIONS`, etc.) is present in both, since those are explicitly
declared in the manifest already — only `INTERNET` was missing.

This is unrelated to issue #42's IPv6 fallback fix (still correct and
unaffected) and unrelated to issue #57/PR #58's R8 minification work —
the manifest gap predates both.

## Fix

Add `<uses-permission android:name="android.permission.INTERNET"/>` to
`AndroidManifest.xml`, alongside the existing `uses-permission` entries.

## Out of scope

- Any change to `ntp_sync_controller.dart`'s sync/retry logic — the
  IPv4-preference and error-handling code is correct as-is; this is a
  manifest-only fix.
- Distinguishing "no INTERNET permission" from other failure causes in the
  UI — the existing generic
  「同期失敗（インターネット接続を確認してください）」message is unchanged.

## Verification

- `dart format` / `flutter analyze` / `flutter test`
- `flutter build apk --release`, `aapt dump permissions` on the resulting
  APK to confirm `android.permission.INTERNET` is now present
- Manual: install the release APK on BlueStacks, tap "サーバー時刻に同期",
  confirm 同期完了 (not 同期失敗)
