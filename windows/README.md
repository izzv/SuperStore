# SuperStore Setup (Windows)

One window that downloads SuperStore, pairs an iPhone over USB, drops the
pairing file into the app and installs the build on the phone.

```
SuperStore-Setup.exe                     # the window
SuperStore-Setup.exe --cli               # same information, in the console
SuperStore-Setup.exe --devices           # iPhones connected over USB
SuperStore-Setup.exe --download          # fetch the stable build
SuperStore-Setup.exe --download --channel development
SuperStore-Setup.exe --pair              # pair, write pairingFile.plist, copy it into the app
SuperStore-Setup.exe --send-pairing      # copy an existing pairing file into the app
SuperStore-Setup.exe --install           # download the chosen channel, then install it
SuperStore-Setup.exe --install C:\path\to\signed.ipa
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
- Installs an `.ipa` with the phone's own install service, with a live progress
  bar, then copies the pairing file in as soon as the app lands.

## What the phone will refuse

iOS only installs apps signed with a development certificate and provisioning
profile that include that specific phone. The build published on the site is
ad-hoc signed, so a direct install ends with `ApplicationVerificationFailed`.
Sign the IPA once with a tool that uses your Apple ID (SideStore, Sideloadly,
AltStore) and install that signed copy through this helper - pairing, the
pairing file and the install itself all work from here.

## How the pairing file reaches the app

SuperStore keeps its pairing file at `Documents/pairingFile.plist` inside its own
container and reads it at launch. The helper writes it through the app's
container service (`com.apple.mobile.house_arrest`), so there is nothing to drag
into the Files app. If SuperStore is not on the phone yet, the file stays in
`%LOCALAPPDATA%\SuperStore\` and "Send to iPhone" copies it across once the app
is installed.

## Build

`.github/workflows/windows-build.yml` builds `SuperStore-Setup.exe` with
PyInstaller on `windows-latest`, bundling `pymobiledevice3` for the device work
and stamping `windows/SuperStore.ico` into the binary and the window.

The build publishes the exe as the only asset of the `windows-setup` release, so
repeated builds replace it instead of piling up copies on the `website` branch.
The download page links straight at
`https://github.com/izzv/SuperStore/releases/download/windows-setup/SuperStore-Setup.exe`,
which keeps the same URL for every build. `SuperStore.ico` is generated from
`branding/superstore-icon-1024.png` with Pillow at the sizes Windows asks for
(16 to 256 px).
