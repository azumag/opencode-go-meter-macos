# OpenCode Go Meter

**English** | [日本語](README.ja.md)

A small native macOS menu bar utility for viewing your OpenCode Go usage, reset times, and an estimated monthly usage pace. Built with Swift, AppKit, Foundation, and UserNotifications; no third-party packages or SwiftPM dependency resolution.

> **Independent, unofficial project.** This app is not built by, affiliated with, or endorsed by OpenCode or Anomaly. It is an experimental personal utility, not a billing authority or a service with guaranteed API compatibility. The application UI and notifications are currently Japanese; this README is available in both languages.

## What it does

- Displays monthly usage in the menu bar and monthly, weekly, and five-hour windows in its menu.
- Calculates an approximate daily/hourly pace from the monthly reset date.
- Sends configurable usage-threshold and unused-budget reminders.
- Optionally starts at login through a per-user LaunchAgent.

The app only monitors usage. It does not send prompts, switch models, buy credits, modify your subscription, or bypass usage limits. “Carryover” is the difference between a locally calculated pace and reported usage **within the current estimated cycle**; it is not an entitlement to roll unused quota into the next billing period. Displayed allowances do not override shorter-window limits.

## Requirements and build

Use a Mac with Apple's Command Line Tools and `swiftc`. Full Xcode is not required. Install the tools with `xcode-select --install` when necessary.

```bash
git clone https://github.com/azumag/opencode-go-meter-macos.git
cd opencode-go-meter-macos
bash scripts/build.sh

dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --selftest
open dist/OpenCodeGoMeter.app
```

The build script compiles in Swift 5 language mode and creates `dist/OpenCodeGoMeter.app`. It attempts ad-hoc signing; this is **not** Developer ID signing or Apple notarization, and signing failure currently produces only a warning. Do not disable macOS security protections to run an untrusted binary.

`Info.plist` declares macOS 13.0, but the build script does not explicitly set a deployment target. Compatibility with older macOS versions and Intel Macs has not been established by this review. Build on the Mac where you intend to run the app; do not interpret the plist value as a tested support matrix.

## Credentials

Use your own OpenCode Go account and API key. The app searches in this order and uses the first nonempty value:

| Priority | Source |
| --- | --- |
| 1 | `OPENCODE_GO_API_KEY` environment variable |
| 2 | `apiKey` in `~/.config/opencode-go-meter/config.json` |
| 3 | `key` under `opencode-go` in `~/.local/share/opencode/auth.json` |

An existing OpenCode login can therefore supply the key without copying it into another file. The app does not modify OpenCode's authentication file. Finder and LaunchAgent launches may not inherit variables exported in a terminal. A stale higher-priority key also prevents fallback to another key; resolution is not retried after an authentication error.

Do not paste real keys into issues, screenshots, shell commands, or this repository. An inference API key should not be treated as a usage-only credential.

## Configuration

On first use, the app creates `~/.config/opencode-go-meter/config.json` with these defaults:

```json
{
  "apiKey": null,
  "pollIntervalSeconds": 120,
  "warnThresholds": [80, 90, 100],
  "unusedReminderHours": [24, 6],
  "unusedReminderMinUsedPercent": 80
}
```

Missing or unreadable settings fall back to defaults. The configuration is reloaded on each fetch. The timer has a 30-second minimum, but opening the menu or selecting refresh also triggers a request; these paths are not currently coalesced or throttled. A changed timer interval is applied after a successful fetch. There is no automatic backoff or `Retry-After` handling yet. Avoid repeated manual refreshes, and quit the app if the service rejects requests.

Use empty arrays for `warnThresholds` and `unusedReminderHours` to disable the corresponding reminders. `OPENCODE_GO_METER_CONFIG_DIR` overrides the meter's configuration/state directory for testing; it does not change the OpenCode authentication-file path.

### Local data and privacy

The configured request target is `https://opencode.ai/zen/go/v1/usage`, authenticated with an `Authorization: Bearer` header. The app has no analytics service, project-operated relay, or web-page scraping code. Normal system networking/proxy behavior still applies.

`config.json` can contain a **plaintext API key**. `state.json` contains recent usage percentages, reset times, fetch time, and notification history. Keys are not intentionally printed or displayed, but usage data and notifications can reveal account activity. `--dump` also prints usage and timestamps; review that output before sharing it.

**Known security limitation:** the current persistence code does not enforce owner-only directory/file permissions. Prefer reusing the existing OpenCode auth file rather than storing an additional key. After the meter has created its directory, restrict access yourself:

```bash
chmod 700 "$HOME/.config/opencode-go-meter"
for file in config.json state.json; do
  path="$HOME/.config/opencode-go-meter/$file"
  if [ -f "$path" ]; then chmod 600 "$path"; fi
done
```

Adjust the path when using a custom configuration directory. This is a local mitigation, not a replacement for hardening the application's file-writing code. See the [publication review](docs/PUBLICATION_REVIEW.ja.md) for remaining work.

## Using the menu

The title shows monthly usage, for example `Go 42%`. Colors change at 75%, 90%, and 100%. The menu includes usage/reset details, pacing estimates, and these actions:

| Japanese label | Meaning |
| --- | --- |
| 今すぐ更新 | Refresh now |
| Console を開く | Open the OpenCode console in your browser |
| 通知をテスト | Test notifications |
| ログイン時に起動 | Toggle launch at login |
| 終了 | Quit |

Notifications use UserNotifications, with an `osascript` fallback when native delivery is unavailable, including when native permission is denied. Check macOS notification settings for both the app and the fallback; the app has no dedicated notification-off switch.

When a request fails, the last successful values remain visible and an error appears in the menu. The menu bar does not currently mark cached/stale values clearly, so check the last-update time and the console before relying on a displayed balance. The meter does not prevent charges: OpenCode documents a console **Use balance** option that can continue usage against Zen credits after a Go limit is reached.

## Install and uninstall

For a per-user installation with launch at login, run after building:

```bash
bash scripts/install.sh
```

This copies the app to `~/Applications/OpenCodeGoMeter.app`, writes `~/Library/LaunchAgents/com.azumag.opencode-go-meter.plist`, and attempts to load the agent. It does not require `sudo`. For a one-off run without installing a LaunchAgent, use `open dist/OpenCodeGoMeter.app` instead.

```bash
bash scripts/uninstall.sh
```

Uninstallation stops the app and removes the installed app and LaunchAgent, but keeps configuration/state. To remove the meter's default local data as well:

```bash
rm -rf "$HOME/.config/opencode-go-meter"
```

Do not delete OpenCode's `auth.json` merely to uninstall this utility. A custom configuration directory must be removed separately. Current LaunchAgent path handling has limitations with special characters; see the review.

## Diagnostics

```bash
# Offline checks; no API call.
dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --selftest

# One authenticated usage request; prints usage/timestamps, not the key.
dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --dump
```

`--dump` returns a nonzero exit code on failure. HTTP 403 is currently displayed as an invalid-key error even though the upstream implementation can also use it for a missing Go subscription. This review did not execute a macOS build, notification test, or authenticated live API request.

## API status and service terms

Reviewed on **2026-09-14**. The usage route exists in [OpenCode's own source](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts). That establishes its origin, **not** a supported public API contract or permission for unrestricted automated polling. The [Go documentation](https://opencode.ai/docs/go/) describes usage limits and model endpoints but did not document this usage route in the reviewed page.

The [service terms](https://opencode.ai/legal/terms-of-service) contain restrictions concerning automated extraction, scraping, unreasonable load, and circumvention. Their application to this particular usage-monitoring workflow has not been confirmed with Anomaly. No written approval or approved polling interval was obtained in this review. This project must not be advertised as approved or unconditionally terms-compliant. Use only authorized credentials; do not add cookie scraping, account rotation, or access-control workarounds. Consult the provider for a definitive interpretation. See also the [provider's privacy policy](https://opencode.ai/legal/privacy-policy).

## Project status and license

The implementation is small and has no third-party package dependencies, but it is not yet a broadly validated release. Outstanding work includes credential-file permissions, request serialization/backoff, strict response validation, stale-data indication, and macOS compatibility testing. Details and evidence are in the [publication review, Japanese](docs/PUBLICATION_REVIEW.ja.md) and the [implementation specification, Japanese](SPEC.md).

**No project license has been selected.** Do not assume that OpenCode's upstream MIT license applies to this separate repository. Public visibility does not by itself grant a general reuse or redistribution license; GitHub's own viewing/forking rights are separate. See [GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
