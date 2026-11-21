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
import time
import uuid
from dataclasses import dataclass
from hashlib import pbkdf2_hmac, sha256
from pathlib import Path

import certifi
import requests
import srp
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

GSA = "https://gsa.apple.com/grandslam/GsService2"
GSA_VALIDATE = "https://gsa.apple.com/grandslam/GsService2/validate"
TRUSTED_DEVICE = "https://gsa.apple.com/auth/verify/trusteddevice"
DEVELOPER = "https://developerservices2.apple.com/services/QH65B2/ios"
ANISETTE_SERVERS = (
    "https://ani.jkcoxson.com",
    "https://mac-ani.jkcoxson.com",
    "https://ani2.stikstore.app",
)
ANISETTE_KEYS = ("X-Apple-I-MD", "X-Apple-I-MD-M", "X-Apple-I-MD-LU")
P12_PASSWORD = "superstore"
PROFILE_LEEWAY = 24 * 3600


class AppleError(Exception):
    """Anything Apple, the network or the local signing step refused."""


class TwoFactorRequired(AppleError):
    """Raised when Apple wants the six-digit code from a trusted device."""


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


class SrpPassword:
    """Apple's password digest for either SRP variant."""

    def __init__(self, password):
        self._digest = sha256(password.encode("utf-8")).digest()
        self.salt = None
        self.iterations = None
        self.key_length = 32
        self.protocol = "s2k"

    def set_encrypt_info(self, salt, iterations, key_length, protocol):
        self.salt = salt
        self.iterations = iterations
        self.key_length = key_length or 32
        self.protocol = protocol or "s2k"

    def encode(self):
        if self.salt is None:
            raise AppleError("Apple did not send a sign-in salt.")
        secret = self._digest.hex().encode() if self.protocol == "s2k_fo" else self._digest
        return pbkdf2_hmac("sha256", secret, self.salt, self.iterations or 1, self.key_length)


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
        self._user = None
        self._proof = None
        self._code = None

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
        if response.status_code >= 400:
            raise AppleError("Apple answered HTTP %s while signing in." % response.status_code)
        try:
            parsed = plistlib.loads(response.content)
        except Exception:
            raise AppleError("Apple did not answer with a sign-in plist.")
        return parsed.get("Response", parsed)

    def begin(self, password):
        self.anisette = self.anisette or fetch_anisette()
        secret = SrpPassword(password)
        srp.rfc5054_enable()
        srp.no_username_in_x()
        user = srp.User(self.apple_id, secret, hash_alg=srp.SHA256, ng_type=srp.NG_2048)
        _, ephemeral = user.start_authentication()
        start = self._gsa({"A2k": ephemeral, "ps": ["s2k", "s2k_fo"], "u": self.apple_id, "o": "init"})
        status = start.get("Status") or {}
        salt = start.get("s")
        server_public = start.get("B")
        if not salt or not server_public:
            raise AppleError(status.get("em") or "Apple did not start the sign-in.")
        secret.set_encrypt_info(salt, int(start.get("i") or 1), int(start.get("kl") or 32), start.get("sp"))
        self._user = user
        self._code = start.get("c")
        proof = user.process_challenge(salt, server_public)
        if proof is None:
            raise AppleError("Apple's sign-in challenge was rejected.")
        self._proof = proof
        answer = self._gsa({"M1": proof, "c": self._code, "u": self.apple_id, "o": "complete"})
        return self._accept(answer)

    def _accept(self, answer):
        status = answer.get("Status") or {}
        if status.get("au"):
            try:
                http().get(TRUSTED_DEVICE, headers=self._headers(), timeout=30)
            except Exception:
                pass
            raise TwoFactorRequired(status.get("em") or "Apple sent a code to your trusted devices.")
        if status.get("ec"):
            raise AppleError(status.get("em") or "Apple refused the sign-in.")
        proof = answer.get("M2")
        if proof:
            self._user.verify_session(proof)
        if not self._user.authenticated():
            raise AppleError("Apple's sign-in proof did not match.")
        return self._session(answer)

    def two_factor(self, code):
        code = "".join(character for character in str(code) if character.isdigit())
        if len(code) < 6:
            raise AppleError("Enter the six-digit code Apple showed on your devices.")
        response = http().get(GSA_VALIDATE, headers=dict(self._headers(), **{"security-code": code}), timeout=45)
        if response.status_code >= 400:
            raise AppleError("Apple rejected the code (HTTP %s)." % response.status_code)
        answer = self._gsa({"M1": self._proof, "c": self._code, "u": self.apple_id, "o": "complete"})
        return self._accept(answer)

    def _session(self, answer):
        dsid = str(answer.get("dsid") or "")
        idms = ""
        payload = answer.get("spd")
        if isinstance(payload, bytes) and payload:
            try:
                decoded = self._decrypt(payload)
                dsid = str(decoded.get("adsid") or dsid)
                idms = str(decoded.get("GsIdmsToken") or "")
            except Exception as error:
                raise AppleError("Could not read the session Apple returned (%s)." % error)
        if not dsid:
            raise AppleError("Apple signed in but returned no account identifier.")
        self.dsid = dsid
        self.token = base64.b64encode(("%s:%s" % (dsid, idms)).encode()).decode()
        return {"dsid": dsid, "identity": self.token, "server": self.anisette.server}

    def _decrypt(self, payload):
        key = self._user.get_session_key()
        aes_key = hmac.new(key, b"extra data key:", hashlib.sha256).digest()
        iv = hmac.new(key, b"extra data iv:", hashlib.sha256).digest()[:16]
        decryptor = Cipher(algorithms.AES(aes_key), modes.CBC(iv)).decryptor()
        plain = decryptor.update(payload) + decryptor.finalize()
        return plistlib.loads(plain[: -plain[-1]])


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
