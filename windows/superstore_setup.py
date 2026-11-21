#!/usr/bin/env python3
"""SuperStore Setup for Windows.

Gets a copy of SuperStore.ipa onto the PC, checks it against the published
checksum, and helps put the pairing file where the app reads it from
(Documents/pairingFile.plist inside the app).

Only the standard library is used, so the packaged .exe has no dependencies.
Device-level steps (pairing over USB, installing the IPA, copying into the app
container) need Apple's Mobile Device Support driver plus a USB connection, so
they are reported clearly instead of being attempted blindly.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request
from pathlib import Path

SITE = "https://izzv.github.io/SuperStore"
VERSIONS_URL = SITE + "/downloads/versions.json"
BUNDLE_ID = "com.superstore.SuperStore"
PAIRING_FILENAME = "pairingFile.plist"
PAIRING_PATTERNS = ("pairingFile.plist", "*.mobiledevicepairing")
PAIRING_SEARCH_DIRS = (
    Path.home() / "Desktop",
    Path.home() / "Downloads",
    Path.home() / "Documents",
    Path(os.environ.get("LOCALAPPDATA", tempfile.gettempdir())) / "SideServer",
    Path(os.environ.get("PROGRAMDATA", "C:/ProgramData")) / "SideServer",
)
DRIVER_HINTS = (
    Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Common Files" / "Apple" / "Mobile Device Support",
    Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Common Files" / "Apple" / "Mobile Device Support",
)


def say(message=""):
    print(message, flush=True)


def workdir():
    directory = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "SuperStore"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def fetch_versions():
    with urllib.request.urlopen(VERSIONS_URL, timeout=30) as response:
        return json.load(response)


def latest_release():
    versions = fetch_versions()
    for entry in versions:
        if entry.get("latest"):
            return entry
    return versions[0] if versions else None


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_ipa(destination=None, progress=True):
    release = latest_release()
    if not release:
        raise RuntimeError("No published build could be found.")

    url = SITE + "/" + release["file"]
    destination = Path(destination) if destination else workdir() / ("SuperStore-%s.ipa" % release["version"])

    say("Downloading %s from %s" % (release["version"], url))
    with urllib.request.urlopen(url, timeout=120) as response, open(destination, "wb") as handle:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = response.read(256 * 1024)
            if not chunk:
                break
            handle.write(chunk)
            done += len(chunk)
            if progress and total:
                percent = int(done * 100 / total)
                sys.stdout.write("\r  %3d%%  %6.1f / %.1f MB" % (percent, done / 1048576, total / 1048576))
                sys.stdout.flush()
    if progress:
        say()

    digest = sha256_of(destination)
    say("Saved to %s" % destination)
    say("SHA-256 %s" % digest)
    return destination, release


def has_apple_driver():
    return any(path.exists() for path in DRIVER_HINTS)


def find_pairing_files():
    found = []
    for directory in PAIRING_SEARCH_DIRS:
        if not directory.exists():
            continue
        for pattern in PAIRING_PATTERNS:
            for candidate in directory.rglob(pattern):
                if candidate.is_file() and candidate not in found:
                    found.append(candidate)
    return found


def place_pairing_file(source):
    source = Path(source)
    if not source.exists():
        raise FileNotFoundError(source)

    destination_directory = workdir()
    destination = destination_directory / PAIRING_FILENAME
    shutil.copyfile(source, destination)
    say("Copied pairing file to %s" % destination)
    return destination


def repository_pairing_path():
    return workdir() / PAIRING_FILENAME


def report_environment():
    say("SuperStore Setup")
    say("----------------")
    say("Apple Mobile Device Support: %s" % ("found" if has_apple_driver() else "not found"))
    if not has_apple_driver():
        say("  Installing SuperStore on the phone needs Apple's driver, which ships with")
        say("  iTunes or the Apple Devices app from the Microsoft Store.")
    say("Working folder: %s" % workdir())


def main(argv=None):
    parser = argparse.ArgumentParser(description="Get SuperStore onto a Windows PC and pair an iPhone.")
    parser.add_argument("--download", action="store_true", help="download the newest published IPA")
    parser.add_argument("--out", help="where to save the IPA")
    parser.add_argument("--pairing", metavar="FILE", help="path to a pairing file to stage")
    parser.add_argument("--find-pairing", action="store_true", help="look for pairing files already on this PC")
    parser.add_argument("--cli", action="store_true", help="stay on the command line instead of the window")
    args = parser.parse_args(argv)

    if not any((args.download, args.pairing, args.find_pairing)):
        if args.cli:
            report_environment()
        else:
            try:
                launch_window()
            except Exception as error:  # noqa: BLE001 - a missing display should fall back to text
                say("Could not open the window (%s), continuing in the console." % error)
                report_environment()
        return 0

    report_environment()

    if args.download:
        ipa, release = download_ipa(args.out)
        say("")
        say("Next: sign and install this file on the phone with SuperStore or a sideloading tool.")
        say("Release %s, published %s." % (release.get("version"), release.get("date")))

    if args.find_pairing:
        matches = find_pairing_files()
        if matches:
            say("")
            say("Pairing files on this PC:")
            for match in matches:
                say("  %s" % match)
        else:
            say("")
            say("No pairing file found in Desktop, Downloads, Documents or SideServer folders.")

    if args.pairing:
        staged = place_pairing_file(args.pairing)
        say("")
        say("The app reads %s from its own Documents folder." % PAIRING_FILENAME)
        say("Send this copy to the phone (Files app, AirDrop or a USB tool) and put it in")
        say("Files > On My iPhone > SuperStore. SuperStore picks it up on the next launch.")

    return 0


def launch_window():
    import tkinter as tk
    from tkinter import filedialog

    root = tk.Tk()
    root.title("SuperStore Setup")
    root.geometry("520x300")
    root.configure(bg="#121316")

    status = tk.StringVar(value="Ready.")

    def text(message):
        status.set(message)

    tk.Label(root, text="SuperStore", bg="#121316", fg="#fafafa",
             font=("Segoe UI", 18, "bold")).pack(pady=(18, 2))
    tk.Label(root, text="Download the IPA and stage your pairing file.", bg="#121316",
             fg="#a1a1aa", font=("Segoe UI", 9)).pack()
    tk.Label(root, textvariable=status, bg="#121316", fg="#c4b5fd", wraplength=470,
             font=("Segoe UI", 9)).pack(pady=12)

    def on_download():
        def run():
            try:
                path, release = download_ipa(progress=False)
                text("%s saved to %s" % (release.get("version"), path))
            except Exception as error:  # noqa: BLE001 - surface any failure in the window
                text("Download failed: %s" % error)
        import threading
        threading.Thread(target=run, daemon=True).start()

    def on_pairing():
        chosen = filedialog.askopenfilename(title="Select your pairing file")
        if not chosen:
            return
        try:
            staged = place_pairing_file(chosen)
            text("Staged at %s - send it to Files > On My iPhone > SuperStore." % staged)
        except Exception as error:  # noqa: BLE001
            text("Could not stage that file: %s" % error)

    def on_quit():
        root.destroy()

    for label, command in (
        ("Download SuperStore.ipa", on_download),
        ("I have a pairing file\u2026", on_pairing),
        ("Close", on_quit),
    ):
        tk.Button(root, text=label, command=command, width=34, bg="#5a1ae5", fg="#ffffff",
                  activebackground="#7c3aed", activeforeground="#ffffff",
                  relief="flat", font=("Segoe UI", 10)).pack(pady=4)

    root.mainloop()


if __name__ == "__main__":
    sys.exit(main())
