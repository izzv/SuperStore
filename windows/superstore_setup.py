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
import tkinter as tk
import tkinter.font as tkfont
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


def say(message=""):
    print(message, flush=True)


def workdir():
    directory = Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "SuperStore"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


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


def download_ipa(destination=None, progress=None, announce=True):
    release = latest_release()
    if not release:
        raise RuntimeError("No published build could be found.")

    url = SITE + "/" + release["file"]
    destination = Path(destination) if destination else workdir() / ("SuperStore-%s.ipa" % release["version"])
    destination.parent.mkdir(parents=True, exist_ok=True)

    if announce:
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
            if progress is not None:
                progress(done, total)
            elif announce and total:
                sys.stdout.write("\r  %3d%%  %6.1f / %.1f MB" % (int(done * 100 / total), done / 1048576, total / 1048576))
                sys.stdout.flush()
    if announce:
        say()
        say("Saved to %s" % destination)
        say("SHA-256 %s" % sha256_of(destination))

    return destination, release


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
    if sys.stdout is None:
        sys.stdout = _NullWriter()
    if sys.stderr is None:
        sys.stderr = _NullWriter()

    logging.getLogger("pymobiledevice3").setLevel(logging.WARNING)

    parser = argparse.ArgumentParser(description="Pair an iPhone and install SuperStore from a Windows PC.")
    parser.add_argument("--cli", action="store_true", help="never open the window")
    parser.add_argument("--devices", action="store_true", help="list iPhones connected over USB")
    parser.add_argument("--download", action="store_true", help="download the newest published IPA")
    parser.add_argument("--out", help="where to save the IPA")
    parser.add_argument("--pair", action="store_true", help="pair over USB and write the pairing file")
    parser.add_argument("--send-pairing", action="store_true", help="copy the pairing file into SuperStore")
    parser.add_argument("--install", metavar="IPA", help="install that .ipa on the connected iPhone")
    parser.add_argument("--pairing", metavar="FILE", help="stage an existing pairing file")
    parser.add_argument("--find-pairing", action="store_true", help="look for pairing files already on this PC")
    args = parser.parse_args(argv)

    wanted = (args.devices, args.download, args.pair, args.send_pairing, args.install, args.pairing, args.find_pairing)
    if not any(wanted):
        if args.cli:
            report_environment()
        else:
            launch_window()
        return 0

    report_environment()
    say("")

    if args.download:
        ipa, release = download_ipa(args.out)
        say("")
        say("Release %s, published %s." % (release.get("version"), release.get("date")))
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

    if args.pair or args.send_pairing or args.install:
        if not serial:
            say("No iPhone found over USB. Connect it, unlock it, and try again.")
            return 1

    if args.pair:
        say("Pairing. Unlock the iPhone and tap Trust if it asks.")
        record, summary = pair_device(serial)
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
        send_pairing_file(serial, pairing)
        say("Copied %s into SuperStore's Documents folder." % pairing)
        say("")

    if args.install:
        say("Installing %s..." % args.install)
        install_ipa(serial, args.install, progress=lambda pct: sys.stdout.write("\r  %3d%%" % pct))
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


class SetupApp:
    def __init__(self):
        global SCALE
        enable_dpi_awareness()
        self.root = tk.Tk()
        self.root.title("SuperStore Setup")
        self.root.configure(bg=BG)
        SCALE = self.root.winfo_fpixels("1i") / 96.0
        self.scale = SCALE
        self.root.geometry("%dx%d" % (px(1020), px(740)))
        self.root.minsize(px(900), px(660))
        dark_title_bar(self.root)

        self.events = queue.Queue()
        self.device = None
        self.pairing_path = existing_pairing_file()
        self.ipa_path = None
        self.release = None
        self.busy = False
        self.polling = False
        self.last_serial = None

        self.build()
        self.log("SuperStore Setup ready.", "ok")
        if not DEVICE_SUPPORT:
            self.log("This copy was built without device support: downloading works, pairing does not.", "error")
        if self.pairing_path:
            self.log("Using the pairing file already on this PC: %s" % self.pairing_path.name, "info")
        self.refresh_buttons()
        self.root.after(120, self.drain)
        self.root.after(300, self.poll_devices)

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
        steps.grid(row=0, column=0, rowspan=2, sticky="nsew", padx=(0, px(14)))
        steps.grid_columnconfigure(0, weight=1)

        device_card = self.card(body)
        device_card.grid(row=0, column=1, sticky="nsew", pady=(0, px(12)))
        log_card = self.card(body)
        log_card.grid(row=1, column=1, sticky="nsew")

        download_step = self.step(steps, "1", "Get the latest build",
                                  "Reads the published version list and downloads the .ipa.")
        self.download_button = Button(download_step["actions"], "Download .ipa", self.on_download)
        self.download_button.pack(side="left")
        self.download_status = download_step["status"]

        pair_step = self.step(steps, "2", "Pair your iPhone",
                              "Unlock the phone and tap Trust when the prompt appears.")
        self.pair_button = Button(pair_step["actions"], "Pair over USB", self.on_pair)
        self.pair_button.pack(side="left")
        self.send_button = Button(pair_step["actions"], "Send to iPhone", self.on_send,
                                  kind="secondary", width=150)
        self.send_button.pack(side="left", padx=(px(8), 0))
        self.pair_status = pair_step["status"]

        install_step = self.step(steps, "3", "Install on iPhone",
                                 "Installs a build signed for this phone, then copies the pairing file across.")
        self.install_button = Button(install_step["actions"], "Install .ipa", self.on_install)
        self.install_button.pack(side="left")
        self.choose_button = Button(install_step["actions"], "Choose file", self.on_choose,
                                    kind="secondary", width=124)
        self.choose_button.pack(side="left", padx=(px(8), 0))
        self.progress = ProgressBar(install_step["frame"].inner, width=360)
        self.progress.pack(fill="x", pady=(px(12), 0))
        self.install_status = install_step["status"]

        notes = self.card(steps)
        notes.pack(fill="both", expand=True, pady=(0, px(12)))
        notes_head = tk.Frame(notes.inner, bg=CARD)
        notes_head.pack(fill="x")
        tk.Label(notes_head, text="Good to know", bg=CARD, fg=TEXT,
                 font=(UI_FONT, 10, "bold"), anchor="w").pack(fill="x")
        for line in (
            "Pairing writes pairingFile.plist and copies it into the app.",
            "iOS only installs a build signed for this phone.",
        ):
            tk.Label(notes.inner, text="·  " + line, bg=CARD, fg=MUTED, font=(UI_FONT, 8), anchor="w",
                     justify="left", wraplength=px(348)).pack(fill="x", pady=(px(5), 0))

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

    def card(self, parent):
        frame = tk.Frame(parent, bg=CARD, highlightbackground=BORDER, highlightthickness=1)
        inner = tk.Frame(frame, bg=CARD)
        inner.pack(fill="both", expand=True, padx=px(16), pady=px(12))
        frame.inner = inner
        return frame

    def step(self, parent, index, title, subtitle):
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
        self.refresh_buttons()

    def on_download(self):
        if self.busy:
            return
        self.set_busy(True)
        self.download_status.configure(text="Downloading…", fg=MUTED)
        self.log("Downloading the newest published build…", "step")

        def work():
            def progress(done, total):
                if total:
                    self.post(self.progress.set, done / total)
            return download_ipa(announce=False, progress=progress)

        self.spawn(work, self.downloaded, self.download_failed)

    def downloaded(self, payload):
        path, release = payload
        self.ipa_path = path
        self.release = release
        self.progress.set(1.0)
        self.download_status.configure(text="%s · %s" % (release.get("version"), path.name), fg=OK)
        self.log("%s downloaded (%s)." % (release.get("version"), human_size(path.stat().st_size)), "ok")
        self.set_busy(False)

    def download_failed(self, error):
        self.download_status.configure(text="Download failed.", fg=ERR)
        self.progress.set(0.0)

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
            self.on_choose()
        if not self.ipa_path:
            return
        self.set_busy(True)
        self.progress.set(0.0)
        self.install_status.configure(text="Installing %s…" % self.ipa_path.name, fg=MUTED)
        self.log("Installing %s on %s…" % (self.ipa_path.name, self.device.get("name", "the iPhone")), "step")
        serial = self.device["serial"]
        path = self.ipa_path

        def work():
            install_ipa(serial, path, progress=lambda pct: self.post(self.progress.set, pct / 100.0))

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
            self.log("iOS only installs builds signed with your Apple ID. The published .ipa is "
                     "unsigned, so sign it once with SideStore or Sideloadly and install that copy here.",
                     "info")

    def open_folder(self):
        try:
            os.startfile(str(workdir()))
        except Exception as error:
            self.log("Could not open %s (%s)." % (workdir(), error), "error")


def hide_console():
    if sys.platform != "win32":
        return
    try:
        handle = ctypes.windll.kernel32.GetConsoleWindow()
        if handle:
            ctypes.windll.user32.ShowWindow(handle, 0)
    except Exception:
        pass


def launch_window():
    hide_console()
    app = SetupApp()
    app.run()


if __name__ == "__main__":
    sys.exit(main())
