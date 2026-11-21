# SuperStore Setup (Windows)

One window that downloads SuperStore, signs in with your Apple ID so Apple
issues a certificate for the phone, pairs an iPhone over USB, drops the pairing
file into the app and installs the signed build on the phone.

```
SuperStore-Setup.exe                     # the window, no console
SuperStore-Setup.exe --cli               # same information, in the console
SuperStore-Setup.exe --apple-id you@example.com --sign-in
SuperStore-Setup.exe --devices           # iPhones connected over USB
SuperStore-Setup.exe --download          # fetch the stable build
SuperStore-Setup.exe --download --channel development
SuperStore-Setup.exe --pair              # pair, write pairingFile.plist, copy it into the app
SuperStore-Setup.exe --send-pairing      # copy an existing pairing file into the app
SuperStore-Setup.exe --install           # download, sign with the cached certificate, install
SuperStore-Setup.exe --install C:\path\to\app.ipa
SuperStore-Setup.exe --find-pairing
SuperStore-Setup.exe --pairing C:\path\to\pairingFile.plist
```

## Channels

Step 1 asks which build to install instead of asking for a file, and both
channels end up as an ordinary `.ipa` in `%LOCALAPPDATA%\SuperStore\`.

- **Stable** - whatever `downloads/versions.json` lists as `latest` on the site,
  so it follows the same release the download page shows.
- **Development** - the newest successful build of `develop`, fetched from the
  `SuperStore-ipa` artifact of the `verify` workflow through nightly.link. The
  archive is unpacked and the real version is read out of the bundle's
  `Info.plist`.

"Choose file" on step 3 still takes a signed `.ipa` if you already have one,
and "Install .ipa" downloads the selected channel first when nothing is on disk
yet.

## Signing in with an Apple ID

Step 2 takes the Apple ID and password you use for Xcode or the App Store.
The helper signs in with Apple directly, asks Apple for a development
certificate and a provisioning profile for the connected iPhone, and signs the
`.ipa` on this PC with them.

- The password is sent to Apple and nowhere else; it is never written to disk.
- Two-factor accounts get the usual code prompt in the window.
- The certificate and profile are cached in `%LOCALAPPDATA%\SuperStore\signing\`,
  so later installs skip the sign-in until the profile runs out. Free accounts
  get seven days per profile; sign in again to renew.
- Apple's sign-in needs machine attestation ("anisette") that Windows cannot
  produce on its own, so the helper asks an anisette server for it. The server
  sees the machine identity, never the Apple ID or the password. The list is at
  the top of `apple_sideload.py`; the first one that answers is used.
- Apple's own error text is shown in the window, so a rejection is legible
  rather than a silent failure.

## What it does

- Offers the stable release and the newest `develop` build, reads the version
  list from the site rather than using a hard-coded link, and saves the IPA to
  `%LOCALAPPDATA%\SuperStore\`.
- Lists iPhones connected over USB through Apple's Mobile Device Service, which
  ships with iTunes or the Apple Devices app and is the only supported way to
  talk to a phone from Windows.
- Pairs the phone (the iPhone shows the usual Trust prompt), writes the pairing
  record to `%LOCALAPPDATA%\SuperStore\pairingFile.plist` and immediately copies
  it into SuperStore's `Documents` folder, where the app reads it at launch.
- Installs the signed `.ipa` with the phone's own install service, with a live
  progress bar, then copies the pairing file in as soon as the app lands.

## What the phone will refuse

iOS only installs apps signed with a development certificate and provisioning
profile that include that specific phone. The published `.ipa` is ad-hoc signed,
which is why the helper signs its own copy before installing. Without a signed-
in Apple ID it falls back to the old behaviour: the phone answers
`ApplicationVerificationFailed`, and the window says so instead of pretending
the install worked.

A free Apple ID limits you to a handful of app identifiers and seven days per
profile, and Apple can revoke the certificate at any time. Signing in again in
step 2 replaces the cached certificate.

## How the pairing file reaches the app

SuperStore keeps its pairing file at `Documents/pairingFile.plist` inside its own
container and reads it at launch. The helper writes it through the app's
container service (`com.apple.mobile.house_arrest`), so there is nothing to drag
into the Files app. If SuperStore is not on the phone yet, the file stays in
`%LOCALAPPDATA%\SuperStore\` and "Send to iPhone" copies it across once the app
is installed.

## Build

`.github/workflows/windows-build.yml` builds `SuperStore-Setup.exe` with
PyInstaller on `windows-latest` in windowed mode, so no console window opens
when the exe is double-clicked; a command-line flag attaches to the console it
was started from instead. The build bundles `pymobiledevice3`, `srp`, `ipasign`,
`cryptography` and certifi, stamps `windows/SuperStore.ico` into the binary and
the window, and ships `windows/apple-root-ca.pem` because Windows does not
trust Apple's root for `gsa.apple.com` by default.

The build publishes the exe as the only asset of the `windows-setup` release, so
repeated builds replace it instead of piling up copies on the `website` branch.
The download page links straight at
`https://github.com/izzv/SuperStore/releases/download/windows-setup/SuperStore-Setup.exe`,
which keeps the same URL for every build. `SuperStore.ico` is generated from
`branding/superstore-icon-1024.png` with Pillow at the sizes Windows asks for
(16 to 256 px).
