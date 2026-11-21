<p align="center">
  <img src="branding/superstore-icon-1024.png" width="120" alt="SuperStore">
</p>

<h1 align="center">SuperStore</h1>

<p align="center">
  <em>An untethered, community-driven sideloading app store for iOS.</em><br>
  Built on <a href="https://github.com/SideStore/SideStore">SideStore</a>, which is itself a fork of
  <a href="https://github.com/rileytestut/AltStore">AltStore</a>.
</p>

<p align="center">
  <a href="https://github.com/izzv/SuperStore/actions/workflows/verify.yml"><img src="https://github.com/izzv/SuperStore/actions/workflows/verify.yml/badge.svg?branch=develop" alt="Verify"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-8b5cf6" alt="License: AGPL-3.0"></a>
  <img src="https://img.shields.io/badge/platform-iOS%2015%2B-lightgrey" alt="Platform: iOS 15+">
  <img src="https://img.shields.io/badge/language-Swift-f05138" alt="Swift">
  <a href="https://github.com/izzv/SuperStore/commits/develop"><img src="https://img.shields.io/github/last-commit/izzv/SuperStore/develop" alt="Last commit"></a>
  <a href="https://izzv.github.io/SuperStore/"><img src="https://img.shields.io/badge/website-live-22d3ee" alt="Website"></a>
</p>

> **SuperStore is a work in progress.** Nothing has been released from this fork yet: it builds (CI compiles it on every push to `develop`), but it has not been signed, installed or tested on a device under the SuperStore name.

---

## What it does

SuperStore is a normal, sandboxed iOS app that sideloads other apps using nothing but your Apple ID. It signs them with your personal development certificate, installs them over a loopback tunnel provided by a VPN, and re-signs them before Apple's seven-day development window expires.

- **No AltServer, no computer, no jailbreak.**
- **Your own certificate** — apps are signed on-device.
- **Background refresh** — apps are re-signed so they keep opening.

## What this fork changes

- **Anisette server failover.** A dead or misbehaving Anisette server used to dump its raw HTML error page into the sign-in alert. SuperStore now tries the next configured server instead, and only reports a failure once every one has failed.
- **Sign-in errors that explain themselves.** Apple's `-80046`, `-80045` and `-22411` come with a plain-language cause and a suggested fix rather than a bare code.
- **Independent branding.** New name, icon set and About screen. Contact and social links live in `AppConstants.Brand` so they can be filled in one place — an unset value hides the control instead of shipping a dead link.

Everything else — sources, installation, refresh, backups — is inherited from SideStore.

## Coming from SideStore

iOS gives every app its own sandbox, so SuperStore cannot read SideStore's data and no app can do that for you. What SuperStore does support is taking the database by hand:

1. Get `SideStore.sqlite` — plus `SideStore.sqlite-wal` and `SideStore.sqlite-shm` if they exist — out of SideStore, using its backup/export tools or a device backup.
2. Copy those files into **Files → On My iPhone → SuperStore**. The app's Documents folder is visible there because it opts into file sharing.
3. Launch SuperStore. The first launch copies them into its own database directory and opens them.

That brings across your sources, the signed-in account record and the list of installed apps. It does **not** bring across the signing certificate, the Anisette data or any app's own data — those live in the keychain, which cannot be moved between apps. Reinstall the apps from the restored sources and they behave as before.

## Requirements

- macOS with Xcode 15 or newer to build
- iOS 15 or newer on the device (CI builds against the current iOS SDK, so the
  newest iOS is covered too)
- [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) installed on the device, which provides the tunnel on-device installation needs

## Building

The app builds unsigned for the arm64 device slice, which needs no certificate, no provisioning profile and no attached device:

```sh
xcodebuild build \
  -project AltStore.xcodeproj \
  -scheme SideStore \
  -config Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

That is exactly what CI runs (`.github/workflows/verify.yml`) on a GitHub-hosted macOS runner.

Do **not** target the simulator: the bundled `minimuxer` and `idevice` libraries ship only an arm64 slice, so `generic/platform=iOS Simulator` fails at link time with undefined symbols.

For signing, provisioning and running on a device, see [CONTRIBUTING.md](./CONTRIBUTING.md).

## How it fits together

| Piece | Role |
| --- | --- |
| `AltStore/`, `SideStore/` | The app itself: sources, app IDs, signing, installation, refresh |
| [SideSign](Dependencies/SideSign) | Apple Developer Services and Anisette client |
| [minimuxer](https://github.com/jkcoxson/minimuxer) | Lockdown muxer that runs inside the iOS sandbox |
| [EM Proxy](https://github.com/jkcoxson/em_proxy) | The loopback tunnel that makes on-device installation possible |

## Activity

<p align="center">
  <a href="https://github.com/izzv/SuperStore/pulse">
    <img src="https://repobeats.axiom.co/api/embed/izzv/SuperStore.svg" alt="Repository activity: contributions, issues, pull requests and pushes over the past month, plus the top contributors" width="100%">
  </a>
</p>

## Contributing

Build instructions, code signing setup and project conventions are in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Licensing

AGPL-3.0. SuperStore is a fork of SideStore, which is a fork of AltStore; both are AGPL-3.0, and the original copyright notices are preserved in [LICENSE](./LICENSE).
