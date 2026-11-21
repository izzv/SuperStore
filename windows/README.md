# SuperStore Setup (Windows)

A small helper that gets the app onto a Windows PC without hunting for the file,
and stages the pairing file so the phone side is a single copy.

```
python superstore_setup.py               # window with two buttons
python superstore_setup.py --cli         # same information, in the console
python superstore_setup.py --download    # fetch the newest published IPA
python superstore_setup.py --find-pairing
python superstore_setup.py --pairing C:\path\to\pairingFile.plist
```

## What it does

- Reads `downloads/versions.json` from the site, so it always takes the newest
  published release rather than a hard-coded link.
- Downloads that IPA to `%LOCALAPPDATA%\SuperStore\` and prints its SHA-256.
- Looks for an existing pairing file in Desktop, Downloads, Documents and the
  SideServer folders, and copies the one you pick to
  `%LOCALAPPDATA%\SuperStore\pairingFile.plist`.
- Reports whether Apple's Mobile Device Support driver is installed, since
  nothing can talk to an iPhone without it.

## What it deliberately does not pretend to do

Pairing a device, installing the IPA over USB and writing into the app's
container all need Apple's USB driver plus libimobiledevice (or pymobiledevice3)
and a connected phone. None of that can be exercised on a build machine, so this
tool does not fake it: it prepares the two files and tells you what is missing.

## How the pairing file reaches the app

SuperStore keeps its pairing file at `Documents/pairingFile.plist` inside its own
container, and reads it at launch. The container is visible in the Files app
because the app opts into file sharing, so dropping the staged file into
**Files → On My iPhone → SuperStore** is enough - no import dialog needed.

## Building the .exe

`.github/workflows/windows-build.yml` builds `SuperStore-Setup.exe` with
PyInstaller on `windows-latest` and uploads it as an artifact. Publishing it as
`downloads/SuperStore-Setup.exe` on the `website` branch makes the Windows button
appear on the downloads page.
