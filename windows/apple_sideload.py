"""Apple ID sign-in, provisioning and signing for the Windows helper.

Signs in with an Apple ID against Apple's GrandSlam service, asks Apple for a
development certificate and a provisioning profile for the connected iPhone,
then signs the .ipa so iOS accepts it. The password only goes to Apple and is
never written to disk; the issued certificate and profile are cached so later
installs do not need it again.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import plistlib
import secrets
import time
import gzip
import uuid
import zlib
from dataclasses import dataclass
from pathlib import Path

import certifi
import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

GSA = "https://gsa.apple.com/grandslam/GsService2"
GSA_VALIDATE = "https://gsa.apple.com/grandslam/GsService2/validate"
TRUSTED_DEVICE = "https://gsa.apple.com/auth/verify/trusteddevice"
SMS_PUT = "https://gsa.apple.com/auth/verify/phone/put?mode=sms"
SMS_VALIDATE = "https://gsa.apple.com/auth/verify/phone/securitycode?referrer=/auth/verify/phone/put"
XCODE_VERSION = "14.2 (14C18)"
TWO_FACTOR_MODES = ("trustedDeviceSecondaryAuth", "secondaryAuth")
INCORRECT_CODE = -21669
DEVELOPER = "https://developerservices2.apple.com/services/QH65B2/ios"
ANISETTE_SERVERS = (
    "https://anisette.lillq.me",
    "https://new.ani.sidestore.io",
    "https://mac-ani.jkcoxson.com",
    "https://ani.iloader.app",
    "https://ani.jkcoxson.com",
    "https://ani2.stikstore.app",
)
ANISETTE_KEYS = ("X-Apple-I-MD", "X-Apple-I-MD-M", "X-Apple-I-MD-LU")
P12_PASSWORD = "superstore"
PROFILE_LEEWAY = 24 * 3600


class AppleError(Exception):
    """Anything Apple, the network or the local signing step refused."""


class TwoFactorRequired(AppleError):
    """Raised when Apple wants the six-digit code from a trusted device."""


class ThrottleHold(AppleError):
    """Raised while Apple's own wait between attempts is still running."""


def workdir():
    directory = Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "SuperStore"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def bundled(name):
    import sys

    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return base / name


def ca_bundle():
    """certifi plus Apple's root, which Windows does not always trust."""
    target = workdir() / "apple-ca-bundle.pem"
    root = bundled("apple-root-ca.pem")
    try:
        stamp = max(certifi.where() and os.path.getmtime(certifi.where()), os.path.getmtime(root))
    except OSError:
        stamp = 0
    if not target.exists() or target.stat().st_mtime < stamp:
        data = Path(certifi.where()).read_bytes()
        if root.exists():
            data += root.read_bytes()
        target.write_bytes(data)
    return str(target)


def http():
    session = requests.Session()
    session.verify = ca_bundle()
    session.headers["Accept-Encoding"] = "identity"
    return session


def attempts_file():
    folder = workdir() / "signing"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "attempts.json"


def is_throttle(status):
    lower = str(status.get("em") or "").lower()
    return "try again later" in lower or "cannot be completed" in lower or "unable to sign you in" in lower


def cooldown_file():
    folder = workdir() / "signing"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "cooldown.json"


def note_throttle(apple_id):
    data = {}
    try:
        data = json.loads(cooldown_file().read_text(encoding="utf-8"))
    except Exception:
        pass
    data[apple_id.lower()] = time.time()
    try:
        cooldown_file().write_text(json.dumps(data), encoding="utf-8")
    except Exception:
        pass


def throttle_wait(apple_id):
    try:
        data = json.loads(cooldown_file().read_text(encoding="utf-8"))
    except Exception:
        return 0
    stamp = data.get(apple_id.lower())
    if not stamp:
        return 0
    return max(0, THROTTLE_COOLDOWN - (time.time() - float(stamp)))


def explain(status):
    code = status.get("ec")
    message = str(status.get("em") or "").strip() or "Apple refused the sign-in."
    label = "%s (Apple code %s)." % (message.rstrip("."), code) if code else message
    lower = message.lower()
    if "locked" in lower:
        label += " Unlock it at appleid.apple.com, then sign in again."
    elif "try again later" in lower or "cannot be completed" in lower or "unable to sign you in" in lower:
        label += (
            " Apple is refusing sign-ins for this Apple ID right now, usually after several attempts."
            " Wait at least an hour before the next try; retrying quickly is what turns this into a"
            " locked account."
        )
    return label


def record_diagnostic(stage, apple_id, status, server):
    lines = [
        "when: %s" % time.strftime("%Y-%m-%d %H:%M:%S"),
        "stage: %s" % stage,
        "apple id: %s" % apple_id,
        "anisette server: %s" % server,
        "status: %r" % (status,),
    ]
    try:
        (workdir() / "last-error.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    except Exception:
        pass


def rejects_credentials(status):
    message = str(status.get("em") or "").lower()
    if any(word in message for word in BLOCKING_WORDS):
        return False
    if status.get("ec") in CREDENTIAL_CODES:
        return True
    return any(word in message for word in CREDENTIAL_WORDS)


def recent_attempts(apple_id):
    try:
        data = json.loads(attempts_file().read_text(encoding="utf-8"))
    except Exception:
        return []
    stamps = data.get(apple_id.lower()) or []
    return [float(stamp) for stamp in stamps if time.time() - float(stamp) < ATTEMPT_WINDOW]


def record_attempt(apple_id):
    data = {}
    try:
        data = json.loads(attempts_file().read_text(encoding="utf-8"))
    except Exception:
        pass
    stamps = [
        stamp for stamp in data.get(apple_id.lower()) or [] if time.time() - float(stamp) < ATTEMPT_WINDOW
    ]
    stamps.append(time.time())
    data[apple_id.lower()] = stamps
    try:
        attempts_file().write_text(json.dumps(data), encoding="utf-8")
    except Exception:
        pass
    return len(stamps)


def clear_attempts(apple_id):
    try:
        data = json.loads(attempts_file().read_text(encoding="utf-8"))
    except Exception:
        return
    if data.pop(apple_id.lower(), None) is not None:
        try:
            attempts_file().write_text(json.dumps(data), encoding="utf-8")
        except Exception:
            pass


SRP_N = int(
    "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC31929"
    "43DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310D"
    "CD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FB"
    "D5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF74"
    "7359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A"
    "436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D"
    "5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E73"
    "03CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6"
    "94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F"
    "9E4AFF73",
    16,
)
SRP_G = 2
SRP_WIDTH = 256
MAX_ATTEMPTS = 5
ATTEMPT_WINDOW = 24 * 3600
THROTTLE_COOLDOWN = 20 * 60
CREDENTIAL_CODES = {-5000, -20970}
CREDENTIAL_WORDS = (
    "entered incorrectly",
    "incorrect",
    "wrong password",
    "password you entered",
    "invalid password",
    "does not match",
)
BLOCKING_WORDS = (
    "locked",
    "disabled",
    "too many",
    "security reasons",
    "try again later",
    "temporarily",
    "could not be completed",
    "not available",
)


def _int_bytes(value):
    if value == 0:
        return b"\x00"
    return value.to_bytes((value.bit_length() + 7) // 8, "big")


def _pad_left(data, width=SRP_WIDTH):
    return data.rjust(width, b"\x00") if len(data) < width else data


class GrandSlamSrp:
    """Apple's SRP-6a variant, which salts the password hash, not the password."""

    def __init__(self):
        self._secret = secrets.randbits(256)
        self._public = pow(SRP_G, self._secret, SRP_N)
        self.key = b""
        self._expected = b""

    def public_key(self):
        return _int_bytes(self._public)

    def proof(self, username, password, salt, iterations, protocol, server_public):
        digest = hashlib.sha256(password.encode("utf-8")).digest()
        seed = digest.hex().encode() if protocol == "s2k_fo" else digest
        passkey = hashlib.pbkdf2_hmac("sha256", seed, salt, max(1, int(iterations or 1)), 32)
        salted = hashlib.sha256(b":" + passkey).digest()
        x = int.from_bytes(hashlib.sha256(salt + salted).digest(), "big")

        server = int.from_bytes(server_public, "big")
        if server % SRP_N == 0:
            raise AppleError("Apple sent an unusable sign-in challenge.")

        scramble = int.from_bytes(
            hashlib.sha256(_pad_left(_int_bytes(self._public)) + _pad_left(_int_bytes(server))).digest(), "big"
        )
        multiplier = int.from_bytes(
            hashlib.sha256(_pad_left(_int_bytes(SRP_N)) + _pad_left(_int_bytes(SRP_G))).digest(), "big"
        )
        verifier = pow(SRP_G, x, SRP_N)
        base = (server - (verifier * multiplier) % SRP_N) % SRP_N
        shared = pow(base, self._secret + scramble * x, SRP_N)
        self.key = hashlib.sha256(_int_bytes(shared)).digest()

        n_hash = hashlib.sha256(_int_bytes(SRP_N)).digest()
        g_hash = hashlib.sha256(_pad_left(_int_bytes(SRP_G))).digest()
        mixed = bytes(left ^ right for left, right in zip(n_hash, g_hash))
        public = _int_bytes(self._public)
        proof = hashlib.sha256(
            mixed + hashlib.sha256(username.encode("utf-8")).digest() + salt + public + server_public + self.key
        ).digest()
        self._expected = hashlib.sha256(public + proof + self.key).digest()
        return proof

    def verify(self, server_proof):
        return bool(server_proof) and hmac.compare_digest(self._expected, server_proof)


@dataclass
class Anisette:
    """The headers Apple expects for a machine identity, plus its own client name."""

    headers: dict
    client_info: str
    user_agent: str
    server: str


def fetch_anisette(preferred=None):
    candidates = []
    if preferred:
        candidates.append(preferred)
    candidates.extend(server for server in ANISETTE_SERVERS if server not in candidates)
    problems = []
    for candidate in candidates:
        base = candidate.rstrip("/")
        try:
            session = http()
            response = session.get(base + "/", timeout=20)
            response.raise_for_status()
            headers = response.json()
            missing = [key for key in ANISETTE_KEYS if not headers.get(key)]
            if missing:
                raise AppleError("missing %s" % ", ".join(missing))
            info = session.get(base + "/v3/client_info", timeout=20)
            meta = info.json() if info.ok else {}
            return Anisette(
                headers={key: str(value) for key, value in headers.items()},
                client_info=meta.get("client_info") or "<MacBookPro13,3> <Mac OS X;10.12.6;16G29> <com.apple.AuthKit/1 (com.apple.akd/1.0)>",
                user_agent=meta.get("user_agent") or "akd/1.0 CFNetwork/811.5.4 Darwin/16.7.0",
                server=base,
            )
        except Exception as error:
            problems.append("%s (%s)" % (base, error))
    raise AppleError("No anisette server answered. " + "; ".join(problems))


class AppleLogin:
    """One Apple ID sign-in, kept around so a 2FA code can be submitted later."""

    def __init__(self, apple_id, anisette=None):
        self.apple_id = apple_id.strip()
        self.anisette = anisette
        self.dsid = ""
        self.token = ""
        self._srp = None
        self._proof = None
        self._code = None
        self._password = ""
        self._identity_token = ""
        self._mode = ""
        self._code_submitted = False

    def _headers(self):
        headers = {
            "Content-Type": "text/x-xml-plist",
            "Accept": "*/*",
            "User-Agent": self.anisette.user_agent,
            "X-Mme-Client-Info": self.anisette.client_info,
            "X-Apple-I-Request-UUID": str(uuid.uuid4()).upper(),
            "X-Apple-Client-App-Name": "akd",
            "Accept-Language": "en-US,en;q=0.9",
        }
        headers.update(self.anisette.headers)
        return headers

    def _gsa(self, payload, headers=None):
        body = dict(payload)
        body.setdefault("cpd", self.anisette.headers)
        document = plistlib.dumps({"Header": {"Version": "1.0.1"}, "Request": body})
        merged = self._headers()
        merged.update(headers or {})
        response = http().post(GSA, data=document, headers=merged, timeout=45)
        try:
            parsed = plistlib.loads(response.content)
        except Exception:
            parsed = None
        if response.status_code >= 400:
            status = ((parsed or {}).get("Response") or {}).get("Status") or {}
            if status.get("au"):
                return parsed["Response"]
            record_diagnostic("gsa http %s" % response.status_code, self.apple_id, status, self.anisette.server)
            if status.get("ec"):
                raise AppleError(explain(status))
            raise AppleError("Apple answered HTTP %s while signing in." % response.status_code)
        if parsed is None:
            raise AppleError("Apple did not answer with a sign-in plist.")
        return parsed.get("Response", parsed)

    def _two_factor_headers(self, extra=None):
        headers = self._headers()
        headers.update(
            {
                "Content-Type": "application/x-plist",
                "Accept": "application/x-buddyml",
                "X-Apple-App-Info": "com.apple.gs.xcode.auth",
                "X-Xcode-Version": XCODE_VERSION,
            }
        )
        if self._identity_token:
            headers["X-Apple-Identity-Token"] = self._identity_token
        headers.update(extra or {})
        return headers

    def begin(self, password, counted=True, retry=False, force=False):
        if not retry:
            self._code_submitted = False
            wait = 0 if force else throttle_wait(self.apple_id)
            if wait:
                raise ThrottleHold(
                    "Apple asked to wait after the last refusal. Try again in %d minutes, or sign in "
                    "at appleid.apple.com meanwhile." % max(1, int(wait // 60))
                )
        if not retry and len(recent_attempts(self.apple_id)) >= MAX_ATTEMPTS:
            raise AppleError(
                "%d failed sign-ins for this Apple ID in the last day. Apple locks accounts after "
                "repeated failures, so sign in at appleid.apple.com first or wait before trying again."
                % MAX_ATTEMPTS
            )
        self._password = password
        self.anisette = self.anisette or fetch_anisette()
        self._srp = GrandSlamSrp()
        start = self._gsa({"A2k": self._srp.public_key(), "ps": ["s2k", "s2k_fo"], "u": self.apple_id, "o": "init"})
        status = start.get("Status") or {}
        salt = start.get("s")
        server_public = start.get("B")
        if not salt or not server_public:
            if status.get("ec"):
                record_diagnostic("init", self.apple_id, status, self.anisette.server)
                raise AppleError(explain(status))
            raise AppleError("Apple did not start the sign-in.")
        self._code = start.get("c")
        self._proof = self._srp.proof(
            self.apple_id,
            password,
            salt,
            int(start.get("i") or 1),
            start.get("sp") or "s2k",
            server_public,
        )
        answer = self._gsa({"M1": self._proof, "c": self._code, "u": self.apple_id, "o": "complete"})
        return self._accept(answer, counted=counted)

    def _accept(self, answer, counted=True):
        status = answer.get("Status") or {}
        if status.get("ec"):
            record_diagnostic("complete", self.apple_id, status, self.anisette.server)
            if is_throttle(status):
                note_throttle(self.apple_id)
            message = explain(status)
            if not counted or not rejects_credentials(status):
                raise AppleError(message)
            count = record_attempt(self.apple_id)
            hint = ""
            if count >= 2:
                hint = (
                    " (Attempt %d today; Apple locks an Apple ID after repeated failures, so check "
                    "the password and the account before trying again.)" % count
                )
            raise AppleError(message + hint)
        if not self._srp.verify(answer.get("M2")):
            raise AppleError("Apple's sign-in proof did not match, so the session was discarded.")
        payload = self._open_payload(answer.get("spd"))
        mode = str(payload.get("url") or status.get("au") or "")
        pending = str(payload.get("status-code") or "") == "409" or mode in TWO_FACTOR_MODES
        if pending:
            adsid = str(payload.get("adsid") or "")
            idms = str(payload.get("GsIdmsToken") or "")
            if adsid and idms:
                self._identity_token = base64.b64encode(("%s:%s" % (adsid, idms)).encode()).decode()
            self._mode = mode or "trustedDeviceSecondaryAuth"
            if self._code_submitted:
                raise AppleError(
                    "Apple accepted the code but asked for one again. Sign out at appleid.apple.com, "
                    "or wait for the pending code to expire, then start the sign-in over."
                )
            self._request_code()
            raise TwoFactorRequired(
                "Apple texted a code to your trusted phone number. Enter it, then press Sign in."
                if self._mode == "secondaryAuth"
                else "Apple sent a code to your trusted devices. Enter it, then press Sign in."
            )
        clear_attempts(self.apple_id)
        self._code_submitted = False
        self._password = ""
        return self._session(answer, payload)

    def _request_code(self):
        try:
            if self._mode == "secondaryAuth":
                body = plistlib.dumps({"serverInfo": {"phoneNumber.id": "1"}})
                response = http().post(SMS_PUT, data=body, headers=self._two_factor_headers(), timeout=45)
                if response.status_code >= 400:
                    raise AppleError(
                        "Apple would not send a text message (HTTP %s). Add a trusted device to the "
                        "Apple ID so the code is pushed there instead." % response.status_code
                    )
            else:
                http().get(TRUSTED_DEVICE, headers=self._two_factor_headers(), timeout=30)
        except AppleError:
            raise
        except Exception:
            pass

    def two_factor(self, code):
        code = "".join(character for character in str(code) if character.isdigit())
        if len(code) < 6:
            raise AppleError("Enter the six-digit code Apple showed on your devices.")
        if not self._password:
            raise AppleError("Enter the Apple ID password again before submitting the code.")
        self._submit_code(code)
        self._code_submitted = True
        return self.begin(self._password, counted=False, retry=True)

    def _submit_code(self, code):
        if self._mode == "secondaryAuth":
            body = plistlib.dumps(
                {"securityCode.code": code, "serverInfo": {"mode": "sms", "phoneNumber.id": "1"}}
            )
            response = http().post(SMS_VALIDATE, data=body, headers=self._two_factor_headers(), timeout=45)
        else:
            response = http().get(
                GSA_VALIDATE, headers=self._two_factor_headers({"security-code": code}), timeout=45
            )
        if response.status_code >= 400:
            raise AppleError(
                "Apple rejected the code (HTTP %s). A fresh code may be needed." % response.status_code
            )
        try:
            parsed = plistlib.loads(response.content)
        except Exception:
            parsed = None
        body = parsed or {}
        status = body.get("Status") or (body.get("Response") or {}).get("Status") or {}
        if status.get("ec"):
            if status.get("ec") == INCORRECT_CODE:
                raise AppleError(
                    "Apple did not accept that code. Codes expire after a few minutes, so request a "
                    "fresh one and enter only the six digits."
                )
            raise AppleError(status.get("em") or "Apple refused the code.")

    def _session(self, answer, payload=None):
        decoded = payload or {}
        dsid = str(decoded.get("adsid") or answer.get("dsid") or "")
        idms = str(decoded.get("GsIdmsToken") or "")
        if not dsid:
            raise AppleError("Apple signed in but returned no account identifier.")
        self.dsid = dsid
        self.token = base64.b64encode(("%s:%s" % (dsid, idms)).encode()).decode()
        return {"dsid": dsid, "identity": self.token, "server": self.anisette.server}

    def _decrypt(self, payload, iv=None):
        key = self._srp.key
        aes_key = hmac.new(key, b"extra data key:", hashlib.sha256).digest()
        iv = iv or hmac.new(key, b"extra data iv:", hashlib.sha256).digest()[:16]
        decryptor = Cipher(algorithms.AES(aes_key), modes.CBC(iv)).decryptor()
        return decryptor.update(payload) + decryptor.finalize()

    def _unpack(self, body):
        if body[:2] == b"\x1f\x8b":
            try:
                return gzip.decompress(body)
            except Exception:
                pass
        if body[:1] == b"\x78":
            try:
                return zlib.decompress(body)
            except Exception:
                pass
        return body

    def _open_payload(self, sealed):
        if isinstance(sealed, dict):
            return sealed
        if not isinstance(sealed, bytes) or not sealed:
            return {}
        if sealed[:6] == b"bplist" or sealed.lstrip()[:1] == b"<":
            try:
                return plistlib.loads(sealed)
            except Exception:
                pass
        tries = [(self._decrypt(sealed), None)]
        if len(sealed) > 32 and len(sealed) % 16 == 0:
            tries.append((self._decrypt(sealed[16:], sealed[:16]), "iv-prefixed"))
        pad = 0
        body = b""
        for raw, _label in tries:
            pad = raw[-1] if raw else 0
            for candidate in (self._unpack(raw[: -pad] if 0 < pad <= 16 else raw), self._unpack(raw)):
                try:
                    return plistlib.loads(candidate)
                except Exception:
                    body = candidate
        record_diagnostic(
            "session payload",
            self.apple_id,
            {
                "ec": 0,
                "em": "unreadable session payload",
                "ciphertext bytes": len(sealed),
                "pad byte": pad,
                "plaintext head": body[:12].hex(),
            },
            self.anisette.server,
        )
        raise AppleError(
            "Could not read the session Apple returned (%s bytes, starts %s)."
            % (len(sealed), body[:4].hex() or "empty")
        )


def clear_throttle(apple_id):
    try:
        data = json.loads(cooldown_file().read_text(encoding="utf-8"))
    except Exception:
        return
    if data.pop(apple_id.lower(), None) is not None:
        try:
            cooldown_file().write_text(json.dumps(data), encoding="utf-8")
        except Exception:
            pass


def check_apple_id(apple_id, anisette=None):
    """Starts a sign-in and stops there, so a real attempt is only spent when Apple is listening."""
    apple_id = apple_id.strip()
    anisette = anisette or fetch_anisette()
    login = AppleLogin(apple_id, anisette)
    start = login._gsa(
        {"A2k": GrandSlamSrp().public_key(), "ps": ["s2k", "s2k_fo"], "u": login.apple_id, "o": "init"}
    )
    status = start.get("Status") or {}
    if start.get("s") and start.get("B"):
        clear_throttle(apple_id)
        return {
            "ok": True,
            "throttled": False,
            "ec": 0,
            "em": "",
            "server": anisette.server,
            "message": "Apple is answering for %s: no wait needed, the sign-in can start (%s)."
            % (apple_id, anisette.server),
        }
    reason = explain(status)
    if is_throttle(status):
        note_throttle(apple_id)
        return {
            "ok": False,
            "throttled": True,
            "ec": status.get("ec"),
            "em": status.get("em"),
            "server": anisette.server,
            "message": "Apple is still refusing sign-ins for %s, so a password would be wasted: %s"
            % (apple_id, reason),
        }
    return {
        "ok": False,
        "throttled": False,
        "ec": status.get("ec"),
        "em": status.get("em"),
        "server": anisette.server,
        "message": "Apple will not accept %s: %s" % (apple_id, reason),
    }


@dataclass
class Identity:
    """Everything needed to sign, cached so the Apple ID is not asked again."""

    apple_id: str
    team_id: str
    bundle_id: str
    p12: bytes
    profile: bytes
    issued: float

    def profile_plist(self):
        return read_profile(self.profile)

    def covers(self, udid):
        plist = self.profile_plist()
        devices = plist.get("ProvisionedDevices") or []
        return udid.upper() in [device.upper() for device in devices]

    def expires(self):
        plist = self.profile_plist()
        expires = plist.get("ExpirationDate")
        if isinstance(expires, float):
            return expires
        return self.issued + 7 * 24 * 3600

    def days_left(self):
        return max(0.0, (self.expires() - time.time()) / 86400.0)


def read_profile(data):
    start = data.find(b"<?xml")
    end = data.find(b"</plist>")
    if start < 0 or end < 0:
        raise AppleError("The provisioning profile Apple returned could not be read.")
    return plistlib.loads(data[start : end + len(b"</plist>")])


def identity_path(apple_id, team_id=""):
    folder = workdir() / "signing"
    folder.mkdir(parents=True, exist_ok=True)
    stamp = hashlib.sha256(apple_id.lower().encode()).hexdigest()[:16]
    return folder / ("%s%s.json" % (stamp, ("-" + team_id) if team_id else ""))


def load_identity_for(udid, apple_id=""):
    folder = workdir() / "signing"
    if not folder.exists():
        return None
    for path in sorted(folder.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if apple_id and str(data.get("apple_id", "")).lower() != apple_id.lower():
            continue
        try:
            identity = Identity(
                apple_id=data["apple_id"],
                team_id=data["team_id"],
                bundle_id=data["bundle_id"],
                p12=base64.b64decode(data["p12"]),
                profile=base64.b64decode(data["profile"]),
                issued=float(data["issued"]),
            )
        except Exception:
            continue
        if identity.days_left() * 86400 < PROFILE_LEEWAY:
            continue
        if not identity.covers(udid):
            continue
        return identity
    return None


def save_identity(identity):
    path = identity_path(identity.apple_id, identity.team_id)
    path.write_text(json.dumps({
        "apple_id": identity.apple_id,
        "team_id": identity.team_id,
        "bundle_id": identity.bundle_id,
        "p12": base64.b64encode(identity.p12).decode(),
        "profile": base64.b64encode(identity.profile).decode(),
        "issued": identity.issued,
    }), encoding="utf-8")
    return path


class Developer:
    """Apple's developer services, the same backend Xcode uses."""

    def __init__(self, login):
        self.login = login

    def _post(self, action, payload):
        body = {
            "clientId": "XABBG36SBA",
            "protocolVersion": "QH65B2",
            "requestId": str(uuid.uuid4()).upper(),
            "userLocale": ["en_US"],
            "DTDK_Platform": "ios",
        }
        body.update(payload)
        headers = {
            "Content-Type": "text/x-xml-plist",
            "Accept": "*/*",
            "User-Agent": self.login.anisette.user_agent,
            "X-Mme-Client-Info": self.login.anisette.client_info,
            "X-Apple-DS-ID": self.login.dsid,
            "X-Apple-Identity-Token": self.login.token,
        }
        headers.update(self.login.anisette.headers)
        response = http().post("%s/%s" % (DEVELOPER, action), data=plistlib.dumps(body), headers=headers, timeout=60)
        if response.status_code >= 400:
            raise AppleError("Apple's developer service answered HTTP %s for %s." % (response.status_code, action))
        try:
            parsed = plistlib.loads(response.content)
        except Exception:
            raise AppleError("Apple's developer service sent an unexpected answer for %s." % action)
        code = parsed.get("resultCode")
        if code not in (None, 0):
            message = parsed.get("userString") or parsed.get("resultString") or "resultCode %s" % code
            raise AppleError("%s (while calling %s)" % (message, action))
        return parsed

    def teams(self):
        teams = self._post("listTeams.action", {}).get("teams") or []
        result = [{"id": str(team.get("teamId") or ""), "name": str(team.get("name") or "")} for team in teams]
        result = [team for team in result if team["id"]]
        if not result:
            raise AppleError("That Apple ID has no developer team. Sign in once in Xcode with it to create a free one.")
        personal = [team for team in result if "personal" in team["name"].lower()]
        return personal + [team for team in result if team not in personal]

    def register_device(self, team_id, udid, name):
        try:
            self._post("addDevice.action", {"teamId": team_id, "deviceNumber": udid, "name": name})
        except AppleError as error:
            if "already" not in str(error).lower():
                raise

    def app_ids(self, team_id):
        return self._post("listAppIds.action", {"teamId": team_id}).get("appIds") or []

    def app_id(self, team_id, bundle_id, app_name):
        for entry in self.app_ids(team_id):
            if str(entry.get("identifier") or "") == bundle_id:
                return str(entry.get("appIdId") or "")
        created = self._post("addAppId.action", {
            "teamId": team_id,
            "identifier": bundle_id,
            "name": app_name[:50],
            "appIdId": str(uuid.uuid4()).upper(),
        })
        return str((created.get("appId") or {}).get("appIdId") or "")

    def certificate(self, team_id, apple_id):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        request = (
            x509.CertificateSigningRequestBuilder()
            .subject_name(x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, "iPhone Developer"),
                x509.NameAttribute(NameOID.EMAIL_ADDRESS, apple_id),
            ]))
            .sign(key, hashes.SHA256())
        )
        answer = self._post("submitDevelopmentCSR.action", {
            "teamId": team_id,
            "csrContent": base64.b64encode(request.public_bytes(serialization.Encoding.DER)).decode(),
        })
        issued = answer.get("certRequest") or {}
        payload = issued.get("certRequestDerEncoded") or issued.get("certificate")
        if payload is None and issued.get("certRequestId"):
            downloaded = self._post("downloadDevelopmentCert.action", {
                "teamId": team_id,
                "certRequestId": str(issued["certRequestId"]),
            })
            issued = downloaded.get("certRequest") or issued
            payload = issued.get("certRequestDerEncoded") or issued.get("certificate")
        if not payload:
            raise AppleError("Apple issued no certificate for this Apple ID.")
        if isinstance(payload, str):
            payload = base64.b64decode(payload)
        certificate = x509.load_der_x509_certificate(bytes(payload))
        key_pem = key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        )
        blob = pkcs12.serialize_key_and_certificates(
            name=b"iPhone Developer",
            key=serialization.load_pem_private_key(key_pem, password=None),
            cert=certificate,
            cas=None,
            encryption_algorithm=serialization.BestAvailableEncryption(P12_PASSWORD.encode()),
        )
        return blob, str(issued.get("certRequestId") or "")

    def profile(self, team_id, app_id_id, udid):
        answer = self._post("downloadTeamProvisioningProfile.action", {
            "teamId": team_id,
            "appIdId": app_id_id,
            "deviceIds": [udid],
        })
        profile = answer.get("provisioningProfile") or {}
        payload = profile.get("encodedProfile")
        if not payload:
            raise AppleError("Apple returned no provisioning profile for this phone.")
        return bytes(payload)


APP_ID = "SuperStore On Device"


def provision(login, udid, device_name, bundle_id, app_name=APP_ID, on_status=None):
    """Ask Apple for a certificate and profile that cover this phone."""

    def say(message):
        if on_status is not None:
            on_status(message)

    developer = Developer(login)
    say("Looking up your developer team…")
    team = developer.teams()[0]
    say("Registering this iPhone with %s…" % (team["name"] or team["id"]))
    developer.register_device(team["id"], udid, device_name or "iPhone")
    say("Preparing the app identifier…")
    app_id = developer.app_id(team["id"], bundle_id, app_name)
    if not app_id:
        raise AppleError("Apple did not return an app identifier for %s." % bundle_id)
    say("Requesting a development certificate…")
    p12, _cert_id = developer.certificate(team["id"], login.apple_id)
    say("Fetching the provisioning profile…")
    profile = developer.profile(team["id"], app_id, udid)
    identity = Identity(
        apple_id=login.apple_id,
        team_id=team["id"],
        bundle_id=bundle_id,
        p12=p12,
        profile=profile,
        issued=time.time(),
    )
    if not identity.covers(udid):
        raise AppleError("The profile Apple returned does not list this iPhone.")
    save_identity(identity)
    return identity


def sign(ipa_path, identity, output_path):
    import ipasign

    result = ipasign.Key(
        _materialise(identity.p12, "p12"),
        _materialise(identity.profile, "mobileprovision"),
        P12_PASSWORD,
    ).sign(str(ipa_path), str(output_path))
    return result


def _materialise(payload, suffix):
    target = workdir() / "signing" / ("identity." + suffix)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)
    return target


def signed_bundle_id(path):
    import zipfile

    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.count("/") == 2 and name.endswith(".app/Info.plist"):
                with archive.open(name) as handle:
                    info = plistlib.load(handle)
                return str(info.get("CFBundleIdentifier") or "")
    return ""
