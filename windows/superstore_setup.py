#!/usr/bin/env python3
"""SuperStore Setup for Windows.

Pairs an iPhone over USB, writes the pairing file SuperStore reads, copies that
file into the app once it is installed, and installs a SuperStore .ipa from the
PC.
"""

import argparse
import asyncio
import ctypes
import hashlib
import json
import logging
import os
import plistlib
import queue
import shutil
import sys
import threading
import time
import traceback
import tkinter as tk
import tkinter.font as tkfont
import urllib.request
import zipfile
from pathlib import Path

try:
    import anisette_server
    import apple_sideload as apple

    SIGNING_SUPPORT = True
except Exception:
    anisette_server = None
    apple = None
    SIGNING_SUPPORT = False

SITE = "https://izzv.github.io/SuperStore"
VERSIONS_URL = SITE + "/downloads/versions.json"
DEVELOPMENT_ZIP = "https://nightly.link/izzv/SuperStore/workflows/verify.yml/develop/SuperStore-ipa.zip"
CHANNELS = (
    {"id": "stable", "label": "Stable", "summary": "the published release"},
    {"id": "development", "label": "Development", "summary": "the newest build of develop"},
)
BUNDLE_ID = "com.superstore.SuperStore"
PAIRING_FILENAME = "pairingFile.plist"
PAIRING_PATTERNS = ("pairingFile.plist", "*.mobiledevicepairing")
PAIRING_SEARCH_DIRS = (
    Path.home() / "Desktop",
    Path.home() / "Downloads",
    Path.home() / "Documents",
    Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "SideServer",
    Path(os.environ.get("PROGRAMDATA", "C:/ProgramData")) / "SideServer",
)
DRIVER_HINTS = (
    Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Common Files" / "Apple" / "Mobile Device Support",
    Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Common Files" / "Apple" / "Mobile Device Support",
)

try:
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.house_arrest import HouseArrestService
    from pymobiledevice3.services.installation_proxy import InstallationProxyService
    from pymobiledevice3.usbmux import list_devices

    DEVICE_SUPPORT = True
except Exception:
    DEVICE_SUPPORT = False

BG = "#0a0b0f"
CARD = "#12141a"
BORDER = "#20242f"
TEXT = "#f2f4f8"
MUTED = "#959dab"
ACCENT = "#7c5cff"
ACCENT_HOVER = "#9075ff"
ACCENT_SOFT = "#241d3d"
ACCENT_TEXT = "#b9a8ff"
OK = "#34d399"
WARN = "#fbbf24"
ERR = "#f87171"
UI_FONT = "Segoe UI"
MONO_FONT = "Consolas"
SCALE = 1.0


def px(value):
    return int(value * SCALE)


def close_splash():
    try:
        import pyi_splash

        pyi_splash.close()
    except Exception:
        pass


def say(message=""):
    print(message, flush=True)


def workdir():
    directory = Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "SuperStore"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def bundled_file(name):
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return base / name


def human_size(size):
    size = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return "%.1f %s" % (size, unit) if unit != "B" else "%d B" % size
        size /= 1024
    return "%.1f GB" % size


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


def describe_build(channel="stable"):
    if channel == "development":
        return {
            "channel": "development",
            "label": "Development",
            "version": "",
            "build": "",
            "date": "",
            "size": "",
            "url": DEVELOPMENT_ZIP,
            "name": "SuperStore-development.ipa",
            "archive": True,
        }

    release = latest_release()
    if not release:
        raise RuntimeError("No published build could be found.")
    return {
        "channel": "stable",
        "label": "Stable",
        "version": str(release.get("version") or ""),
        "build": "",
        "date": str(release.get("date") or ""),
        "size": str(release.get("size") or ""),
        "url": SITE + "/" + release["file"],
        "name": Path(release["file"]).name,
        "archive": False,
    }


def ipa_identity(path):
    try:
        with zipfile.ZipFile(path) as ipa:
            for name in ipa.namelist():
                if name.count("/") == 2 and name.endswith(".app/Info.plist"):
                    info = plistlib.loads(ipa.read(name))
                    return {
                        "version": str(info.get("CFBundleShortVersionString") or ""),
                        "build": str(info.get("CFBundleVersion") or ""),
                        "bundle_id": str(info.get("CFBundleIdentifier") or ""),
                    }
    except Exception:
        pass
    return {"version": "", "build": "", "bundle_id": ""}


def _stream(url, destination, progress=None, announce=False):
    with urllib.request.urlopen(url, timeout=120) as response, open(destination, "wb") as handle:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = response.read(256 * 1024)
            if not chunk:
                break
            handle.write(chunk)
            done += len(chunk)
            if progress is not None:
                progress(done, total)
            elif announce and total:
                sys.stdout.write("\r  %3d%%  %6.1f / %.1f MB" % (int(done * 100 / total), done / 1048576, total / 1048576))
                sys.stdout.flush()
    if announce:
        say()


def download_build(channel="stable", destination=None, progress=None, announce=True):
    build = describe_build(channel)
    destination = Path(destination) if destination else workdir() / build["name"]
    destination.parent.mkdir(parents=True, exist_ok=True)

    if announce:
        say("Downloading the %s build from %s" % (build["label"].lower(), build["url"]))

    if build["archive"]:
        archive_path = destination.with_suffix(".zip")
        _stream(build["url"], archive_path, progress, announce)
        with zipfile.ZipFile(archive_path) as archive:
            entry = next((name for name in archive.namelist() if name.lower().endswith(".ipa")), None)
            if entry is None:
                raise RuntimeError("The development archive did not contain an .ipa.")
            destination.write_bytes(archive.read(entry))
        archive_path.unlink(missing_ok=True)
    else:
        _stream(build["url"], destination, progress, announce)

    identity = ipa_identity(destination)
    for key in ("version", "build", "bundle_id"):
        build[key] = identity.get(key, "")

    if announce:
        say("Saved to %s" % destination)
        if build["version"]:
            say("Version %s (build %s)" % (build["version"], build["build"]))
        say("SHA-256 %s" % sha256_of(destination))

    return destination, build


def existing_pairing_file():
    path = workdir() / PAIRING_FILENAME
    return path if path.exists() else None


def save_pairing_record(record, destination=None):
    if not record:
        raise RuntimeError("The iPhone did not return a pairing record.")

    destination = Path(destination) if destination else workdir() / PAIRING_FILENAME
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(record))
    return destination


def has_apple_driver():
    return any(path.exists() for path in DRIVER_HINTS)


def connected_devices():
    if not DEVICE_SUPPORT:
        return []
    try:
        devices = asyncio.run(list_devices())
    except Exception:
        return []
    return [device for device in devices if device.is_usb]


def device_summary(serial):
    if not DEVICE_SUPPORT:
        return None
    try:
        return asyncio.run(_device_summary(serial))
    except Exception:
        return {"serial": serial, "name": "iPhone", "model": "", "ios": "", "paired": False}


async def _device_summary(serial):
    async with await create_using_usbmux(serial=serial, autopair=False) as lockdown:
        return {
            "serial": serial,
            "name": lockdown.display_name or "iPhone",
            "model": lockdown.product_type or "",
            "ios": lockdown.product_version or "",
            "paired": bool(lockdown.paired),
        }


def pair_device(serial=None, timeout=180):
    if not DEVICE_SUPPORT:
        raise RuntimeError("This copy has no device support.")
    return asyncio.run(_pair_device(serial, timeout))


async def _pair_device(serial, timeout):
    async with await create_using_usbmux(serial=serial, autopair=True, pair_timeout=timeout) as lockdown:
        record = dict(lockdown.pair_record or {})
        summary = {
            "serial": lockdown.identifier or serial,
            "name": lockdown.display_name or "iPhone",
            "model": lockdown.product_type or "",
            "ios": lockdown.product_version or "",
            "paired": bool(lockdown.paired),
        }
    return record, summary


def send_pairing_file(serial, path):
    if not DEVICE_SUPPORT:
        raise RuntimeError("This copy has no device support.")
    return asyncio.run(_send_pairing_file(serial, path))


async def _send_pairing_file(serial, path):
    async with await create_using_usbmux(serial=serial, autopair=True) as lockdown:
        async with await HouseArrestService.create(lockdown, BUNDLE_ID, documents_only=True) as container:
            await container.push(Path(path), PAIRING_FILENAME, progress_bar=False)


def install_ipa(serial, path, progress=None):
    if not DEVICE_SUPPORT:
        raise RuntimeError("This copy has no device support.")
    return asyncio.run(_install_ipa(serial, path, progress))


async def _install_ipa(serial, path, progress):
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(path)

    async with await create_using_usbmux(serial=serial, autopair=True) as lockdown:
        async with InstallationProxyService(lockdown) as service:
            def handler(percent, *_):
                if progress is not None:
                    progress(int(percent or 0))

            await service.install_from_local(path, handler=handler, developer=True)


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

    destination = workdir() / PAIRING_FILENAME
    shutil.copyfile(source, destination)
    return destination


def report_environment():
    say("SuperStore Setup")
    say("----------------")
    say("Device support: %s" % ("ready" if DEVICE_SUPPORT else "unavailable"))
    say("Apple Mobile Device Support: %s" % ("found" if has_apple_driver() else "not found"))
    if not has_apple_driver():
        say("  Pairing and installation need Apple's driver, which ships with iTunes or")
        say("  the Apple Devices app.")
    say("Signing support: %s" % ("ready" if SIGNING_SUPPORT else "unavailable"))
    say("Working folder: %s" % workdir())

    devices = connected_devices()
    if not devices:
        say("iPhones over USB: none")
        return

    for device in devices:
        summary = device_summary(device.serial) or {}
        detail = ", ".join(part for part in (summary.get("model"), summary.get("ios")) if part)
        say("iPhone: %s%s (%s)" % (summary.get("name") or "iPhone", (" - " + detail) if detail else "", device.serial))


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    if any(argument.startswith("-") for argument in arguments):
        attach_console()
    if sys.stdout is None:
        sys.stdout = _NullWriter()
    if sys.stderr is None:
        sys.stderr = _NullWriter()

    logging.getLogger("pymobiledevice3").setLevel(logging.WARNING)

    parser = argparse.ArgumentParser(description="Pair an iPhone and install SuperStore from a Windows PC.")
    parser.add_argument("--cli", action="store_true", help="never open the window")
    parser.add_argument("--devices", action="store_true", help="list iPhones connected over USB")
    parser.add_argument("--download", action="store_true", help="download a build")
    parser.add_argument("--out", help="where to save the IPA")
    parser.add_argument("--channel", choices=[channel["id"] for channel in CHANNELS], default="stable",
                        help="which build to download (default: stable)")
    parser.add_argument("--pair", action="store_true", help="pair over USB and write the pairing file")
    parser.add_argument("--send-pairing", action="store_true", help="copy the pairing file into SuperStore")
    parser.add_argument("--install", nargs="?", const="", metavar="IPA",
                        help="install that .ipa, or download the chosen channel and install it")
    parser.add_argument("--apple-id", metavar="EMAIL", help="Apple ID to sign the build with")
    parser.add_argument("--sign-in", action="store_true", help="sign in and cache a certificate for this iPhone")
    parser.add_argument("--check-apple-id", metavar="EMAIL",
                        help="ask Apple whether it will accept this Apple ID right now, without a password")
    parser.add_argument("--force", action="store_true", help="sign in even if Apple asked to wait")
    parser.add_argument("--anisette-server", metavar="URL",
                        help="Anisette server to use, e.g. http://192.168.1.20:6969")
    parser.add_argument("--pairing", metavar="FILE", help="stage an existing pairing file")
    parser.add_argument("--find-pairing", action="store_true", help="look for pairing files already on this PC")
    args = parser.parse_args(argv)
    if args.anisette_server:
        apple.PREFERRED_ANISETTE = args.anisette_server.strip()

    wanted = (args.devices, args.download, args.pair, args.send_pairing, args.install is not None,
              args.pairing, args.find_pairing, args.sign_in, bool(args.apple_id),
              bool(args.check_apple_id))
    if not any(wanted):
        if args.cli:
            report_environment()
        else:
            launch_window()
        return 0

    report_environment()
    say("")

    if args.download:
        try:
            ipa, build = download_build(args.channel, args.out)
        except Exception as error:
            say("Download failed: %s" % error)
            return 1
        say("")
        say("%s build %s" % (build["label"], build["version"] or "of unknown version"))
        if build["date"]:
            say("Published %s." % build["date"])
        say("")
        say("Install it on the phone with: --install %s" % ipa)
        say("")

    if args.find_pairing:
        matches = find_pairing_files()
        if matches:
            say("Pairing files on this PC:")
            for match in matches:
                say("  %s" % match)
        else:
            say("No pairing file found in Desktop, Downloads, Documents or SideServer folders.")
        say("")

    if args.pairing:
        staged = place_pairing_file(args.pairing)
        say("Staged at %s" % staged)
        say("")

    serial = None
    devices = connected_devices()
    if devices:
        serial = devices[0].serial

    if args.pair or args.send_pairing or args.install or args.sign_in or args.apple_id:
        if not serial:
            say("No iPhone found over USB. Connect it, unlock it, and try again.")
            return 1

    if args.pair:
        say("Pairing. Unlock the iPhone and tap Trust if it asks.")
        try:
            record, summary = pair_device(serial)
        except Exception as error:
            say("Pairing failed: %s" % error)
            return 1
        pairing = save_pairing_record(record)
        say("Paired %s (iOS %s)." % (summary.get("name"), summary.get("ios")))
        say("Pairing file: %s" % pairing)
        try:
            send_pairing_file(serial, pairing)
            say("Copied into SuperStore's Documents folder.")
        except Exception as error:
            say("SuperStore is not on the phone yet, so the pairing file stayed on the PC.")
            say("  %s" % error)
        say("")

    if args.send_pairing:
        pairing = existing_pairing_file()
        if not pairing:
            say("No pairing file yet. Run --pair first.")
            return 1
        try:
            send_pairing_file(serial, pairing)
        except Exception as error:
            say("Could not copy the pairing file into the app: %s" % error)
            return 1
        say("Copied %s into SuperStore's Documents folder." % pairing)
        say("")

    if args.check_apple_id:
        if not SIGNING_SUPPORT:
            say("Signing support is unavailable in this build.")
            return 1
        result = apple.check_apple_id(args.check_apple_id)
        say(result["message"])
        return 0 if result["ok"] else 1

    if args.sign_in or args.apple_id:
        import getpass

        email = (args.apple_id or input("Apple ID: ")).strip()
        login = apple.AppleLogin(email)
        try:
            login.begin(getpass.getpass("Password: "), force=args.force)
        except apple.TwoFactorRequired:
            login.two_factor(input("Two-factor code: ").strip())
        except apple.AppleError as error:
            say("Apple refused the sign-in: %s" % error)
            return 1
        summary = device_summary(serial) or {}
        try:
            identity = apple.provision(login, serial, summary.get("name") or "iPhone", BUNDLE_ID, on_status=say)
        except apple.AppleError as error:
            say("Could not get a certificate from Apple: %s" % error)
            return 1
        say("Signed in as %s (team %s)." % (identity.apple_id, identity.team_id))
        say("Certificate valid for %d more days; installs are signed on this PC." % int(identity.days_left()))
        say("")

    if args.install is not None:
        target = args.install
        if not target:
            try:
                target, _build = download_build(args.channel)
            except Exception as error:
                say("Download failed: %s" % error)
                return 1
        identity = apple.load_identity_for(serial, args.apple_id or "") if SIGNING_SUPPORT else None
        if identity is None:
            say("No Apple ID certificate for this iPhone yet.")
            say("Run with --apple-id you@example.com to sign in first, then install again.")
            return 1
        signed = workdir() / "SuperStore-signed.ipa"
        say("Signing %s for this iPhone..." % target)
        try:
            apple.sign(target, identity, signed)
        except Exception as error:
            say("Signing failed: %s" % error)
            return 1
        target = signed
        say("Installing %s..." % target)
        try:
            install_ipa(serial, target, progress=lambda pct: sys.stdout.write("\r  %3d%%" % pct))
        except Exception as error:
            say()
            say("Install failed: %s" % error)
            if "verification" in str(error).lower():
                say("iOS refused the signature. Check that the profile Apple issued lists this")
                say("iPhone, then run --apple-id again to renew it.")
            return 1
        say("")
        say("Installed.")
        pairing = existing_pairing_file()
        if pairing:
            try:
                send_pairing_file(serial, pairing)
                say("Pairing file copied into the app.")
            except Exception as error:
                say("Could not copy the pairing file: %s" % error)
        say("")

    return 0


class _NullWriter:
    def write(self, *_):
        return 0

    def flush(self):
        pass

    def isatty(self):
        return False


def enable_dpi_awareness():
    if sys.platform != "win32":
        return
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


def dark_title_bar(root):
    if sys.platform != "win32":
        return
    try:
        root.update_idletasks()
        handle = ctypes.windll.user32.GetParent(root.winfo_id())
        enabled = ctypes.c_int(1)
        ctypes.windll.dwmapi.DwmSetWindowAttribute(handle, 20, ctypes.byref(enabled), ctypes.sizeof(enabled))
    except Exception:
        pass


def round_rect(canvas, x1, y1, x2, y2, radius, **options):
    radius = min(radius, (x2 - x1) / 2, (y2 - y1) / 2)
    points = (
        x1 + radius, y1, x2 - radius, y1, x2, y1, x2, y1 + radius,
        x2, y2 - radius, x2, y2, x2 - radius, y2, x1 + radius, y2,
        x1, y2, x1, y2 - radius, x1, y1 + radius, x1, y1,
    )
    return canvas.create_polygon(points, smooth=True, **options)


class Button(tk.Canvas):
    def __init__(self, master, text, command, width=176, height=36, kind="primary", bg=CARD):
        super().__init__(master, width=px(width), height=px(height), bg=bg, highlightthickness=0, bd=0, cursor="hand2")
        self.command = command
        self.label = text
        self.kind = kind
        self.box_width = px(width)
        self.box_height = px(height)
        self.enabled = True
        self.hovered = False
        self.font = (UI_FONT, 9, "bold")
        self.bind("<Enter>", self._enter)
        self.bind("<Leave>", self._leave)
        self.bind("<ButtonPress-1>", self._press)
        self.bind("<ButtonRelease-1>", self._release)
        self.draw()

    def draw(self):
        self.delete("all")
        if not self.enabled:
            fill, outline, foreground = "#171a21", "#242935", "#5a6270"
        elif self.kind == "primary":
            fill = ACCENT_HOVER if self.hovered else ACCENT
            outline = fill
            foreground = "#ffffff"
        else:
            fill = "#20242f" if self.hovered else "#191c24"
            outline = "#2b3240"
            foreground = "#e4e8f0"
        round_rect(self, 1, 1, self.box_width - 1, self.box_height - 1, px(10), fill=fill, outline=outline, width=1)
        self.create_text(self.box_width / 2, self.box_height / 2 + 1, text=self.label, fill=foreground, font=self.font)

    def set_enabled(self, enabled):
        self.enabled = enabled
        self.configure(cursor="hand2" if enabled else "arrow")
        if not enabled:
            self.hovered = False
        self.draw()

    def _enter(self, _event):
        if self.enabled:
            self.hovered = True
            self.draw()

    def _leave(self, _event):
        self.hovered = False
        self.draw()

    def _press(self, _event):
        if self.enabled:
            self.draw()

    def _release(self, _event):
        if self.enabled and self.command is not None:
            self.command()


class Pill(tk.Canvas):
    def __init__(self, master, text, color=WARN, bg=BG):
        super().__init__(master, width=px(150), height=px(24), bg=bg, highlightthickness=0, bd=0)
        self.bg = bg
        self.label = text
        self.color = color
        self.font = (UI_FONT, 9, "bold")
        self.draw()

    def draw(self):
        self.delete("all")
        width = tkfont.Font(font=self.font).measure(self.label) + px(30)
        height = px(24)
        self.configure(width=width, height=height)
        round_rect(self, 1, 1, width - 1, height - 1, height / 2, fill=self.color, outline="")
        self.create_oval(px(9), height / 2 - px(3), px(15), height / 2 + px(3), fill=BG, outline="")
        self.create_text(px(21), height / 2, anchor="w", text=self.label, fill=BG, font=self.font)

    def set(self, text, color):
        self.label = text
        self.color = color
        self.draw()


class ProgressBar(tk.Canvas):
    def __init__(self, master, width=350, height=6, bg=CARD):
        super().__init__(master, width=px(width), height=px(height), bg=bg, highlightthickness=0, bd=0)
        self.bar_width = px(width)
        self.bar_height = px(height)
        self.value = 0.0
        self.draw()

    def draw(self):
        self.delete("all")
        round_rect(self, 0, 0, self.bar_width, self.bar_height, self.bar_height / 2, fill="#252b38", outline="")
        if self.value > 0:
            span = max(self.bar_height, self.bar_width * self.value)
            round_rect(self, 0, 0, span, self.bar_height, self.bar_height / 2, fill=ACCENT, outline="")

    def set(self, value):
        self.value = max(0.0, min(1.0, value))
        self.draw()


class Chip(tk.Canvas):
    def __init__(self, master, text, command, width=124, height=30, bg=CARD):
        super().__init__(master, width=px(width), height=px(height), bg=bg, highlightthickness=0, bd=0, cursor="hand2")
        self.label = text
        self.command = command
        self.active = False
        self.hovered = False
        self.box_width = px(width)
        self.box_height = px(height)
        self.font = (UI_FONT, 9, "bold")
        self.bind("<Enter>", self._enter)
        self.bind("<Leave>", self._leave)
        self.bind("<Button-1>", self._click)
        self.draw()

    def draw(self):
        self.delete("all")
        if self.active:
            fill, outline, foreground = ACCENT, ACCENT, "#ffffff"
        elif self.hovered:
            fill, outline, foreground = "#232936", "#333b4d", "#e4e8f0"
        else:
            fill, outline, foreground = "#171a22", "#2a3140", "#c7cedb"
        round_rect(self, 1, 1, self.box_width - 1, self.box_height - 1, self.box_height / 2,
                   fill=fill, outline=outline, width=1)
        self.create_text(self.box_width / 2, self.box_height / 2 + 1, text=self.label, fill=foreground,
                         font=self.font)

    def set_active(self, active):
        self.active = active
        self.draw()

    def _enter(self, _event):
        self.hovered = True
        self.draw()

    def _leave(self, _event):
        self.hovered = False
        self.draw()

    def _click(self, _event):
        if self.command is not None:
            self.command()


class Segmented(tk.Frame):
    def __init__(self, master, options, command, bg=CARD):
        super().__init__(master, bg=bg)
        self.command = command
        self.chips = {}
        self.value = options[0][0]
        for index, (value, label) in enumerate(options):
            chip = Chip(self, label, lambda option=value: self.select(option), bg=bg)
            chip.pack(side="left", padx=(0 if index == 0 else px(6), 0))
            self.chips[value] = chip
        self.refresh()

    def select(self, value):
        if self.value == value:
            return
        self.value = value
        self.refresh()
        if self.command is not None:
            self.command(value)

    def refresh(self):
        for value, chip in self.chips.items():
            chip.set_active(value == self.value)


class SetupApp:
    def __init__(self):
        global SCALE
        enable_dpi_awareness()
        self.root = tk.Tk()
        self.root.title("SuperStore Setup")
        icon = bundled_file("SuperStore.ico")
        if icon.exists():
            try:
                self.root.iconbitmap(default=str(icon))
            except tk.TclError:
                pass
        self.root.configure(bg=BG)
        SCALE = self.root.winfo_fpixels("1i") / 96.0
        self.scale = SCALE
        self.root.geometry("%dx%d" % (px(1020), px(880)))
        self.root.minsize(px(900), px(740))
        dark_title_bar(self.root)

        self.events = queue.Queue()
        self.device = None
        self.pairing_path = existing_pairing_file()
        self.ipa_path = None
        self.identity = None
        self.login = None
        self.anisette_host = None
        self.release = None
        self.channel = "stable"
        self.stable_note = ""
        self.pending_install = False
        self.busy = False
        self.force_sign_in = False
        self.polling = False
        self.last_serial = None

        self.build()
        close_splash()
        self.log("SuperStore Setup ready.", "ok")
        if not DEVICE_SUPPORT:
            self.log("This copy was built without device support: downloading works, pairing does not.", "error")
        if not SIGNING_SUPPORT:
            self.account_status.configure(text="This build cannot sign in: installs would stay unsigned.", fg=ERR)
            self.log("This copy was built without signing support; the Apple ID step is disabled.", "error")
        if self.pairing_path:
            self.log("Using the pairing file already on this PC: %s" % self.pairing_path.name, "info")
        self.refresh_buttons()
        self.root.after(120, self.drain)
        self.root.after(300, self.poll_devices)
        self.root.after(600, self.resolve_stable)

    def run(self):
        self.root.mainloop()

    def build(self):
        pad = 24
        header = tk.Frame(self.root, bg=BG)
        header.pack(fill="x", padx=pad, pady=(px(20), 4))
        brand = tk.Frame(header, bg=BG)
        brand.pack(side="left")
        tk.Label(brand, text="SuperStore", bg=BG, fg=TEXT, font=(UI_FONT, 22, "bold")).pack(side="left")
        tk.Label(brand, text="SETUP", bg=ACCENT_SOFT, fg=ACCENT_TEXT, font=(UI_FONT, 8, "bold"),
                 padx=7, pady=3).pack(side="left", padx=(px(10), 0), pady=(px(6), 0))
        self.status_pill = Pill(header, "Waiting for iPhone", WARN, bg=BG)
        self.status_pill.pack(side="right", pady=(px(6), 0))

        body = tk.Frame(self.root, bg=BG)
        body.pack(fill="both", expand=True, padx=pad, pady=(px(10), 0))
        body.grid_columnconfigure(0, weight=0, minsize=px(410))
        body.grid_columnconfigure(1, weight=1)
        body.grid_rowconfigure(1, weight=1)

        steps = tk.Frame(body, bg=BG)
        steps.grid(row=0, column=0, rowspan=3, sticky="nsew", padx=(0, px(14)))
        steps.grid_columnconfigure(0, weight=1)

        device_card = self.card(body)
        device_card.grid(row=0, column=1, sticky="nsew", pady=(0, px(12)))
        log_card = self.card(body)
        log_card.grid(row=1, column=1, sticky="nsew")
        notes_card = self.card(body)
        notes_card.grid(row=2, column=1, sticky="ew", pady=(px(12), 0))

        download_step = self.step(steps, "1", "Choose your build",
                                  "Stable is the published release; Development follows develop.",
                                  before=self.build_channels)
        self.download_button = Button(download_step["actions"], "Download .ipa", self.on_download)
        self.download_button.pack(side="left")
        self.download_status = download_step["status"]
        self.download_progress = ProgressBar(download_step["frame"].inner, width=360)
        self.download_progress.pack(fill="x", pady=(px(8), 0))

        account_step = self.step(steps, "2", "Sign in with Apple ID",
                                 "Apple signs the build for this iPhone. The password only goes to Apple.",
                                 before=self.build_account)
        self.sign_button = Button(account_step["actions"], "Sign in", self.on_sign_in)
        self.sign_button.pack(side="left")
        self.check_button = Button(account_step["actions"], "Check Apple", self.on_check_apple,
                                   kind="secondary", width=130)
        self.check_button.pack(side="left", padx=(px(8), 0))
        self.force_button = Button(account_step["actions"], "Try anyway", self.on_force,
                                   kind="secondary", width=120)
        self.account_status = account_step["status"]

        pair_step = self.step(steps, "3", "Pair your iPhone",
                              "Unlock the phone and tap Trust when the prompt appears.")
        self.pair_button = Button(pair_step["actions"], "Pair over USB", self.on_pair)
        self.pair_button.pack(side="left")
        self.send_button = Button(pair_step["actions"], "Send to iPhone", self.on_send,
                                  kind="secondary", width=150)
        self.send_button.pack(side="left", padx=(px(8), 0))
        self.pair_status = pair_step["status"]

        install_step = self.step(steps, "4", "Install on iPhone",
                                 "Installs a build signed for this phone, then copies the pairing file across.")
        self.install_button = Button(install_step["actions"], "Install .ipa", self.on_install)
        self.install_button.pack(side="left")
        self.choose_button = Button(install_step["actions"], "Choose file", self.on_choose,
                                    kind="secondary", width=124)
        self.choose_button.pack(side="left", padx=(px(8), 0))
        self.progress = ProgressBar(install_step["frame"].inner, width=360)
        self.progress.pack(fill="x", pady=(px(12), 0))
        self.install_status = install_step["status"]

        notes = notes_card
        notes_head = tk.Frame(notes.inner, bg=CARD)
        notes_head.pack(fill="x")
        tk.Label(notes_head, text="Good to know", bg=CARD, fg=TEXT,
                 font=(UI_FONT, 10, "bold"), anchor="w").pack(fill="x")
        for line in (
            "Signing in asks Apple for a certificate for this phone.",
            "Pairing writes pairingFile.plist and copies it into the app.",
        ):
            tk.Label(notes.inner, text="·  " + line, bg=CARD, fg=MUTED, font=(UI_FONT, 8), anchor="w",
                     justify="left", wraplength=px(470)).pack(fill="x", pady=(px(5), 0))

        device_inner = device_card.inner
        device_head = tk.Frame(device_inner, bg=CARD)
        device_head.pack(fill="x")
        tk.Label(device_head, text="Device", bg=CARD, fg=TEXT, font=(UI_FONT, 11, "bold")).pack(side="left")
        tk.Label(device_head, text="USB", bg=CARD, fg=MUTED, font=(UI_FONT, 8)).pack(side="right")
        self.device_name = tk.Label(device_inner, text="No iPhone detected", bg=CARD, fg=TEXT,
                                    font=(UI_FONT, 14, "bold"), anchor="w")
        self.device_name.pack(fill="x", pady=(px(10), px(2)))
        self.device_detail = tk.Label(device_inner, text="Connect the iPhone with a USB cable and unlock it.",
                                      bg=CARD, fg=MUTED, font=(UI_FONT, 9), anchor="w", justify="left",
                                      wraplength=px(500))
        self.device_detail.pack(fill="x")

        log_inner = log_card.inner
        log_head = tk.Frame(log_inner, bg=CARD)
        log_head.pack(fill="x")
        tk.Label(log_head, text="Activity", bg=CARD, fg=TEXT, font=(UI_FONT, 11, "bold")).pack(side="left")
        Button(log_head, "Clear", self.clear_log, kind="secondary", width=68, height=24).pack(side="right")
        self.log_text = tk.Text(log_inner, bg="#0e1016", fg="#c7cedb", bd=0, relief="flat", wrap="word",
                                highlightthickness=1, highlightbackground=BORDER, padx=px(10), pady=px(8),
                                font=(MONO_FONT, 9), spacing1=1, spacing3=2, height=9)
        self.log_text.pack(fill="both", expand=True, pady=(px(10), 0))
        self.log_text.tag_configure("time", foreground="#59616f")
        self.log_text.tag_configure("info", foreground="#c7cedb")
        self.log_text.tag_configure("step", foreground=ACCENT_TEXT)
        self.log_text.tag_configure("ok", foreground=OK)
        self.log_text.tag_configure("error", foreground=ERR)
        self.log_text.configure(state="disabled")
        self.log_text.bind("<MouseWheel>", lambda event: self.log_text.yview_scroll(int(-event.delta / 120), "units"))

        footer = tk.Frame(self.root, bg=BG)
        footer.pack(fill="x", padx=pad, pady=(px(10), px(16)))
        tk.Label(footer, text="Pairing file: %s" % (workdir() / PAIRING_FILENAME), bg=BG, fg=MUTED,
                 font=(UI_FONT, 8)).pack(side="left")
        Button(footer, "Open folder", self.open_folder, kind="secondary", width=110, height=26).pack(side="right")

    def build_account(self, parent):
        email_row, self.account_email = self.field(parent, "Apple ID", 28)
        password_row, self.account_password = self.field(parent, "Password", 28, secret=True)
        self.code_row, self.account_code = self.field(parent, "Code", 10)
        self.code_row.pack_forget()
        self.password_row = password_row
        self.anisette_row, self.anisette_entry = self.field(parent, "Anisette", 28)
        self.anisette_entry.insert(0, apple.PREFERRED_ANISETTE)
        host_row = tk.Frame(parent, bg=CARD)
        host_row.pack(fill="x", pady=(px(6), 0))
        self.host_button = Button(host_row, "Host one here", self.on_host_anisette,
                                  kind="secondary", width=118, height=26)
        self.host_button.pack(side="left", padx=(px(74), 0))
        self.host_note = tk.Label(host_row, text="Runs an Anisette server on this PC", bg=CARD,
                                  fg=MUTED, font=(UI_FONT, 8), anchor="w")
        self.host_note.pack(side="left", padx=(px(8), 0))

    def field(self, parent, label, width, secret=False):
        row = tk.Frame(parent, bg=CARD)
        row.pack(fill="x", pady=(px(6), 0))
        tk.Label(row, text=label, bg=CARD, fg=MUTED, font=(UI_FONT, 8), width=9,
                 anchor="w").pack(side="left")
        entry = tk.Entry(row, bg="#0e1016", fg=TEXT, insertbackground=TEXT, bd=0, relief="flat",
                         highlightthickness=1, highlightbackground=BORDER, highlightcolor=ACCENT,
                         font=(UI_FONT, 9), width=width, show="*" if secret else "")
        entry.pack(side="left", ipady=px(4), padx=(px(4), 0))
        return row, entry

    def on_check_apple(self):
        if self.busy or not SIGNING_SUPPORT:
            return
        email = self.account_email.get().strip()
        if "@" not in email:
            self.account_status.configure(
                text="Enter the Apple ID you use for Xcode or the App Store, then check again.", fg=ERR)
            return
        self.set_busy(True)
        self.account_status.configure(text="Asking Apple whether it will talk to this PC…", fg=MUTED)

        def work():
            return apple.check_apple_id(email)

        def done(result):
            self.set_busy(False)
            self.account_status.configure(text=result["message"], fg=OK if result["ok"] else WARN)
            self.log(result["message"], "ok" if result["ok"] else "info")
            if result["ok"]:
                self.force_button.pack_forget()

        self.spawn(work, done, self.sign_in_failed)

    def on_force(self):
        if self.busy:
            return
        self.force_sign_in = True
        self.force_button.pack_forget()
        self.on_sign_in()

    def on_sign_in(self):
        if self.busy or not SIGNING_SUPPORT:
            return
        if self.identity is not None:
            self.log("Already signed in as %s." % self.identity.apple_id, "ok")
            return
        email = self.account_email.get().strip()
        password = self.account_password.get()
        code = self.account_code.get().strip()
        if "@" not in email:
            self.account_status.configure(text="Enter the Apple ID you use for Xcode or the App Store.", fg=ERR)
            return
        if not self.device:
            self.account_status.configure(text="Connect the iPhone first so Apple can register it.", fg=WARN)
            return
        if password or code:
            self.log("Signing in as %s…" % email, "step")
        apple.PREFERRED_ANISETTE = self.anisette_entry.get().strip()
        self.set_busy(True)
        self.account_status.configure(text="Talking to Apple…", fg=MUTED)
        serial = self.device["serial"]
        name = self.device.get("name") or "iPhone"

        def work():
            if self.login is None or self.login.apple_id.lower() != email.lower():
                self.login = apple.AppleLogin(email)
            if not self.login.dsid:
                if code:
                    self.login.two_factor(code)
                else:
                    if not password:
                        raise apple.AppleError("Enter the Apple ID password in step 2.")
                    try:
                        self.login.begin(password, force=self.force_sign_in)
                    except apple.TwoFactorRequired as need:
                        self.post(self.ask_for_code, str(need))
                        return "code"
            return apple.provision(self.login, serial, name, BUNDLE_ID,
                                   on_status=lambda text: self.post(self.account_note, text))

        self.spawn(work, self.signed_in, self.sign_in_failed)

    def on_host_anisette(self):
        if self.anisette_host is not None:
            host, self.anisette_host = self.anisette_host, None
            host.stop()
            self.host_button.label = "Host one here"
            self.host_button.draw()
            self.host_note.configure(text="Server stopped", fg=MUTED)
            self.log("Anisette server stopped.", "info")
            return
        if anisette_server is None:
            self.host_note.configure(text="Anisette hosting is unavailable in this build", fg=ERR)
            return
        self.host_button.label = "Starting…"
        self.host_button.draw()
        self.host_note.configure(text="Asking an upstream server for a machine identity…", fg=MUTED)

        def work():
            host = anisette_server.AnisetteHost(port=6969)
            host.start()
            host.warm()
            return host, host.address()

        def done(result):
            host, address = result
            self.anisette_host = host
            apple.PREFERRED_ANISETTE = address
            self.anisette_entry.delete(0, "end")
            self.anisette_entry.insert(0, address)
            self.host_button.label = "Stop"
            self.host_button.draw()
            self.host_note.configure(text="Serving on port %d" % host.port, fg=OK)
            self.log("Anisette server running. Public: %s · network: %s" % (address, host.local_address()), "ok")
            if address == host.local_address():
                self.log("The public address could not be looked up, so devices on this PC's network "
                         "should use %s." % address, "info")
            else:
                self.log("If the public address does not answer from outside, forward TCP %d on your "
                         "router." % host.port, "info")

        self.spawn(work, done, self.host_failed)

    def host_failed(self, error):
        self.anisette_host = None
        self.host_button.label = "Host one here"
        self.host_button.draw()
        self.host_note.configure(text=("Could not start it: %s" % str(error))[:70], fg=ERR)

    def account_note(self, text):
        self.account_status.configure(text=text, fg=MUTED)

    def ask_for_code(self, message=None):
        self.account_password.delete(0, "end")
        self.code_row.pack(after=self.password_row, fill="x", pady=(px(6), 0))
        self.account_code.focus_set()
        self.account_status.configure(
            text=message or "Apple sent a code to your trusted devices. Enter it, then press Sign in.",
            fg=WARN)
        self.log("Two-factor authentication: enter the code Apple showed, then press Sign in again.", "info")

    def signed_in(self, identity):
        if identity == "code":
            self.set_busy(False)
            return
        self.identity = identity
        self.code_row.pack_forget()
        self.account_code.delete(0, "end")
        self.account_password.delete(0, "end")
        self.account_status.configure(
            text="Signed in as %s  ·  certificate good for %d more days" % (identity.apple_id, int(identity.days_left())),
            fg=OK)
        self.log("Apple issued a certificate for this iPhone. Installs are signed on this PC now.", "ok")
        self.set_busy(False)

    def sign_in_failed(self, error):
        message = str(error) or "Apple refused the sign-in."
        self.account_status.configure(text=message, fg=ERR)
        self.log(message, "error")
        if isinstance(error, apple.ThrottleHold) and not self.busy:
            self.force_button.pack(side="left", padx=(px(8), 0))

    def restore_identity(self):
        if not SIGNING_SUPPORT or self.identity is not None or not self.device:
            return
        identity = apple.load_identity_for(self.device["serial"])
        if identity is None:
            return
        self.identity = identity
        self.account_email.delete(0, "end")
        self.account_email.insert(0, identity.apple_id)
        self.account_status.configure(
            text="Signed in as %s  ·  certificate good for %d more days" % (identity.apple_id, int(identity.days_left())),
            fg=OK)
        self.refresh_buttons()

    def card(self, parent):
        frame = tk.Frame(parent, bg=CARD, highlightbackground=BORDER, highlightthickness=1)
        inner = tk.Frame(frame, bg=CARD)
        inner.pack(fill="both", expand=True, padx=px(16), pady=px(10))
        frame.inner = inner
        return frame

    def step(self, parent, index, title, subtitle, before=None):
        card = self.card(parent)
        card.pack(fill="x", pady=(0, px(10)))
        inner = card.inner
        head = tk.Frame(inner, bg=CARD)
        head.pack(fill="x")
        tk.Label(head, text=index, bg=ACCENT_SOFT, fg=ACCENT_TEXT, font=(UI_FONT, 9, "bold"),
                 width=2, pady=px(2)).pack(side="left", padx=(0, px(10)))
        titles = tk.Frame(head, bg=CARD)
        titles.pack(side="left", fill="x", expand=True)
        tk.Label(titles, text=title, bg=CARD, fg=TEXT, font=(UI_FONT, 11, "bold"), anchor="w").pack(fill="x")
        tk.Label(titles, text=subtitle, bg=CARD, fg=MUTED, font=(UI_FONT, 8), anchor="w").pack(fill="x")
        if before is not None:
            before(inner)
        actions = tk.Frame(inner, bg=CARD)
        actions.pack(fill="x", pady=(px(10), 0))
        status = tk.Label(inner, text="", bg=CARD, fg=MUTED, font=(UI_FONT, 8), anchor="w", justify="left",
                          wraplength=px(360))
        status.pack(fill="x", pady=(px(6), 0))
        return {"frame": card, "actions": actions, "status": status}

    def post(self, callback, *args):
        self.events.put((callback, args))

    def drain(self):
        while True:
            try:
                callback, args = self.events.get_nowait()
            except queue.Empty:
                break
            try:
                callback(*args)
            except Exception:
                pass
        self.root.after(80, self.drain)

    def log(self, message, tag="info"):
        self.post(self.append_log, message, tag)

    def append_log(self, message, tag):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", time.strftime("%H:%M") + "  ", "time")
        self.log_text.insert("end", message + "\n", tag)
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def clear_log(self):
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")

    def spawn(self, work, done=None, failed=None):
        def target():
            try:
                result = work()
            except Exception as error:
                self.post(self.finish_error, failed, error)
                return
            if done is not None:
                self.post(done, result)
        threading.Thread(target=target, daemon=True).start()

    def finish_error(self, handler, error):
        self.log(str(error) or error.__class__.__name__, "error")
        if handler is not None:
            handler(error)
        self.set_busy(False)

    def set_busy(self, busy):
        self.busy = busy
        self.refresh_buttons()

    def refresh_buttons(self):
        ready = bool(self.device) and not self.busy
        self.download_button.set_enabled(not self.busy)
        self.pair_button.set_enabled(ready)
        self.send_button.set_enabled(ready and bool(self.pairing_path))
        self.install_button.set_enabled(ready)
        self.choose_button.set_enabled(not self.busy)
        self.sign_button.set_enabled(SIGNING_SUPPORT and not self.busy and self.identity is None)
        self.check_button.set_enabled(SIGNING_SUPPORT and not self.busy)

    def poll_devices(self):
        if DEVICE_SUPPORT and not self.polling and not self.busy:
            self.polling = True
            threading.Thread(target=self.poll_worker, daemon=True).start()
        self.root.after(3000, self.poll_devices)

    def poll_worker(self):
        try:
            devices = connected_devices()
            summary = device_summary(devices[0].serial) if devices else None
        except Exception:
            summary = None
        self.polling = False
        self.post(self.apply_device, summary)

    def apply_device(self, summary):
        serial = summary.get("serial") if summary else None
        if serial == self.last_serial:
            if summary:
                self.device = summary
            return
        self.last_serial = serial
        self.device = summary
        if summary:
            name = summary.get("name") or "iPhone"
            detail = "  ·  ".join(part for part in (summary.get("model"),
                                                    ("iOS " + summary["ios"]) if summary.get("ios") else "",
                                                    summary.get("serial")) if part)
            self.device_name.configure(text=name)
            self.device_detail.configure(text=detail)
            self.status_pill.set("iPhone connected", OK)
            self.log("%s connected over USB." % name, "ok")
        else:
            self.device_name.configure(text="No iPhone detected")
            self.device_detail.configure(text="Connect the iPhone with a USB cable and unlock it.")
            self.status_pill.set("Waiting for iPhone", WARN)
        self.restore_identity()
        self.refresh_buttons()

    def build_channels(self, parent):
        row = tk.Frame(parent, bg=CARD)
        row.pack(fill="x", pady=(px(10), 0))
        options = tuple((channel["id"], channel["label"]) for channel in CHANNELS)
        self.channel_picker = Segmented(row, options, self.on_channel)
        self.channel_picker.pack(side="left")
        self.channel_note = tk.Label(row, text="checking the published release…", bg=CARD, fg=MUTED,
                                     font=(UI_FONT, 8), anchor="w")
        self.channel_note.pack(side="left", padx=(px(10), 0))

    def on_channel(self, value):
        if self.busy:
            return
        self.channel = value
        self.download_status.configure(text="", fg=MUTED)
        self.download_progress.set(0.0)
        if value == "development":
            self.channel_note.configure(text="newest successful build of develop")
            self.log("Development builds come from the newest green build of develop.", "info")
        else:
            self.channel_note.configure(text=self.stable_note or "published release")

    def resolve_stable(self):
        self.spawn(lambda: describe_build("stable"), self.stable_described, self.stable_unavailable)

    def stable_described(self, build):
        summary = next(channel["summary"] for channel in CHANNELS if channel["id"] == "stable")
        parts = [build["version"], build["date"], build["size"]]
        self.stable_note = "  ·  ".join(part for part in parts if part) or summary
        if self.channel == "stable":
            self.channel_note.configure(text=self.stable_note)

    def stable_unavailable(self, _error):
        self.channel_note.configure(text="could not read the release list")

    def on_download(self):
        if self.busy:
            return
        self.set_busy(True)
        self.download_progress.set(0.0)
        label = next(channel["label"] for channel in CHANNELS if channel["id"] == self.channel)
        self.download_status.configure(text="Downloading the %s build…" % label.lower(), fg=MUTED)
        self.log("Downloading the %s build…" % label.lower(), "step")

        def work():
            def progress(done, total):
                if total:
                    self.post(self.download_progress.set, done / total)
            return download_build(self.channel, announce=False, progress=progress)

        self.spawn(work, self.downloaded, self.download_failed)

    def downloaded(self, payload):
        path, build = payload
        self.ipa_path = path
        self.release = build
        self.download_progress.set(1.0)

        version = build["version"] or ""
        if version and not version.lower().startswith("v"):
            version = "v" + version
        detail = "  ·  ".join(part for part in (
            version,
            ("build " + build["build"]) if build["build"] else "",
            path.name,
        ) if part)

        self.download_status.configure(text=detail, fg=OK)
        self.log("%s build downloaded: %s." % (build["label"], detail), "ok")
        if self.channel == "development" and build["version"]:
            self.channel_note.configure(text="develop %s (%s)" % (version, build["build"] or "?"))
        if build.get("bundle_id") and build["bundle_id"] != BUNDLE_ID:
            self.log("That .ipa is %s, not %s." % (build["bundle_id"], BUNDLE_ID), "error")
        self.set_busy(False)
        if self.pending_install:
            self.pending_install = False
            self.on_install()

    def download_failed(self, error):
        self.pending_install = False
        self.download_status.configure(text="Download failed.", fg=ERR)
        self.download_progress.set(0.0)

    def on_pair(self):
        if self.busy or not self.device:
            return
        self.set_busy(True)
        self.pair_status.configure(text="Waiting for the Trust prompt…", fg=MUTED)
        self.log("Pairing %s. Unlock it and tap Trust." % self.device.get("name", "the iPhone"), "step")
        serial = self.device["serial"]
        self.spawn(lambda: pair_device(serial), self.paired, self.pair_failed)

    def paired(self, payload):
        record, summary = payload
        path = save_pairing_record(record)
        self.pairing_path = path
        self.device = summary
        self.pair_status.configure(text="pairingFile.plist written to %s" % path, fg=OK)
        self.log("Pairing file written (%s)." % human_size(path.stat().st_size), "ok")
        self.log("Copying the pairing file into SuperStore…", "step")
        self.push_pairing()

    def pair_failed(self, _error):
        self.pair_status.configure(text="Pairing did not finish.", fg=ERR)

    def push_pairing(self):
        if not self.device or not self.pairing_path:
            self.set_busy(False)
            return
        serial = self.device["serial"]
        path = self.pairing_path
        self.spawn(lambda: send_pairing_file(serial, path), self.pairing_sent, self.pairing_send_failed)

    def pairing_sent(self, _result):
        self.pair_status.configure(text="Pairing file is in SuperStore's Documents folder.", fg=OK)
        self.log("SuperStore will pick the pairing file up the next time it launches.", "ok")
        self.install_status.configure(text="", fg=MUTED)
        self.set_busy(False)

    def pairing_send_failed(self, error):
        message = str(error)
        if "not installed" in message.lower() or "lookupfailed" in message.lower():
            self.pair_status.configure(text="Pairing file saved on the PC.", fg=WARN)
            self.log("SuperStore is not on the phone yet. Install it, then press Send to iPhone.", "info")
        else:
            self.pair_status.configure(text="Could not reach the app's folder.", fg=ERR)

    def on_send(self):
        if self.busy or not self.device or not self.pairing_path:
            return
        self.set_busy(True)
        self.pair_status.configure(text="Copying to the iPhone…", fg=MUTED)
        self.log("Copying %s into SuperStore's Documents folder…" % self.pairing_path.name, "step")
        self.push_pairing()

    def on_choose(self):
        if self.busy:
            return
        from tkinter import filedialog

        chosen = filedialog.askopenfilename(title="Choose an .ipa", filetypes=(("iOS app", "*.ipa"), ("All files", "*.*")))
        if not chosen:
            return
        self.ipa_path = Path(chosen)
        self.install_status.configure(text="Using %s" % self.ipa_path.name, fg=MUTED)
        self.log("Selected %s (%s)." % (self.ipa_path.name, human_size(self.ipa_path.stat().st_size)), "info")

    def on_install(self):
        if self.busy or not self.device:
            return
        if not self.ipa_path:
            label = next(channel["label"] for channel in CHANNELS if channel["id"] == self.channel)
            self.pending_install = True
            self.log("No build downloaded yet. Fetching the %s build first…" % label.lower(), "step")
            self.on_download()
            return
        serial = self.device["serial"]
        path = self.ipa_path
        identity = self.identity or (apple.load_identity_for(serial) if SIGNING_SUPPORT else None)
        if identity is None:
            self.install_status.configure(text="Sign in with your Apple ID in step 2 first.", fg=WARN)
            self.log("Apple has to sign this build for the phone before it can install.", "info")
            return

        self.identity = identity
        self.set_busy(True)
        self.progress.set(0.0)
        self.install_status.configure(text="Signing %s for this iPhone…" % path.name, fg=MUTED)
        self.log("Signing %s with the certificate Apple issued to %s…" % (path.name, identity.apple_id), "step")
        signed = workdir() / "SuperStore-signed.ipa"

        def work():
            apple.sign(path, identity, signed)
            self.post(self.install_status.configure, "Signed. Sending it to the iPhone…", MUTED)
            self.post(self.log, "Signed copy ready (%s). Installing…" % human_size(signed.stat().st_size), "step")
            install_ipa(serial, signed, progress=lambda pct: self.post(self.progress.set, pct / 100.0))

        self.spawn(work, self.installed, self.install_failed)

    def installed(self, _result):
        self.progress.set(1.0)
        self.install_status.configure(text="Installed.", fg=OK)
        self.log("Installed. Sign in on the phone to finish setting up SuperStore.", "ok")
        if self.pairing_path:
            self.log("Copying the pairing file into the app…", "step")
            self.push_pairing()
        else:
            self.set_busy(False)

    def install_failed(self, error):
        message = str(error)
        self.install_status.configure(text="The phone refused the build.", fg=ERR)
        if "verification" in message.lower():
            self.log("iOS refused the signature. Check that the profile Apple issued lists this "
                     "iPhone, then sign in again to renew it.", "info")

    def open_folder(self):
        try:
            os.startfile(str(workdir()))
        except Exception as error:
            self.log("Could not open %s (%s)." % (workdir(), error), "error")


def console_stream(handle_id):
    import msvcrt

    kernel32 = ctypes.windll.kernel32
    handle = kernel32.GetStdHandle(handle_id)
    if handle in (None, 0, ctypes.c_void_p(-1).value) or kernel32.GetFileType(handle) == 0:
        return None
    descriptor = msvcrt.open_osfhandle(handle, os.O_WRONLY | os.O_TEXT)
    return open(descriptor, "w", encoding="utf-8", errors="replace", buffering=1, closefd=False)


def attach_console():
    if sys.platform != "win32" or sys.stdout is not None:
        return
    try:
        kernel32 = ctypes.windll.kernel32
        if not kernel32.AttachConsole(-1):
            kernel32.AllocConsole()
        sys.stdout = console_stream(-11) or open("CONOUT$", "w", encoding="utf-8", errors="replace", buffering=1)
        sys.stderr = console_stream(-12) or open("CONOUT$", "w", encoding="utf-8", errors="replace", buffering=1)
        sys.stdin = open("CONIN$", "r", encoding="utf-8", errors="replace")
    except Exception:
        pass


def report_crash():
    target = workdir() / "last-error.txt"
    try:
        target.write_text(traceback.format_exc(), encoding="utf-8")
    except Exception:
        target = None
    try:
        ctypes.windll.user32.MessageBoxW(
            None,
            "SuperStore Setup hit an error and stopped.\n\n%s" % ("Details: %s" % target if target else ""),
            "SuperStore Setup",
            0x10,
        )
    except Exception:
        pass


def launch_window():
    try:
        app = SetupApp()
        app.run()
    except Exception:
        close_splash()
        report_crash()


if __name__ == "__main__":
    sys.exit(main())
