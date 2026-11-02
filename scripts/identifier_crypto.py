#!/usr/bin/env python3
"""Reference implementation of identifier protection (docs/phase-2-model/12-tax-id-security-design.md, DEC-25).

The consuming application must do exactly this; the database holds neither the plaintext nor the keys.
  canonicalise(type, value) -> str    reject bad input; one canonical form per identifier
  encrypt(...)  -> (ciphertext, bidx, key_version)    AES-256-GCM, random 96-bit nonce; AAD binds the row context
  decrypt(...)  -> canonical str
Keys: TALENTRA_IDENTIFIER_ROOT_KEY, 32 bytes as 64 hex characters, from a secret store or a 0400 file. Two keys are derived
with HKDF-SHA-256 and distinct labels (encryption, blind index). Versioned: TALENTRA_IDENTIFIER_ROOT_KEY_V<n> selects an older
root for decrypting rows not yet rotated. For seeding and tests only, `dev_root_key()` returns a fixed key and says so.
"""
import hashlib, hmac, os, re, sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

CURRENT_VERSION = 1
_ALNUM36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


class IdentifierError(ValueError):
    pass


def _gstin_check_char(first14):
    total = 0
    for i, ch in enumerate(first14):
        v = _ALNUM36.index(ch) * (1 if i % 2 == 0 else 2)
        total += v // 36 + v % 36
    return _ALNUM36[(36 - total % 36) % 36]


def canonicalise(identifier_type, value):
    """One canonical form per type. Separators and case never create a second identity; a failed check digit is rejected, not repaired."""
    if not isinstance(value, str) or not value.strip():
        raise IdentifierError("identifier is empty")
    v = value.strip().upper()
    if identifier_type == "gstin":
        v = re.sub(r"[\s-]", "", v)
        if not re.fullmatch(r"\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]", v):
            raise IdentifierError("GSTIN has the wrong shape")
        if _gstin_check_char(v[:14]) != v[14]:
            raise IdentifierError("GSTIN check digit does not match")
    elif identifier_type == "pan":
        v = re.sub(r"[^0-9A-Z]", "", v)
        if not re.fullmatch(r"[A-Z]{5}\d{4}[A-Z]", v):
            raise IdentifierError("PAN has the wrong shape")
    elif identifier_type == "cin":
        v = re.sub(r"\s", "", v)
        if not re.fullmatch(r"[LU]\d{5}[A-Z]{2}\d{4}[A-Z]{3}\d{6}", v):
            raise IdentifierError("CIN has the wrong shape")
    elif identifier_type == "ein":
        v = re.sub(r"[^0-9]", "", v)
        if not re.fullmatch(r"\d{9}", v):
            raise IdentifierError("EIN must have 9 digits")
        v = f"{v[:2]}-{v[2:]}"
    elif identifier_type in ("vat", "company_number"):
        v = re.sub(r"[^0-9A-Z]", "", v)
        if not 4 <= len(v) <= 20:
            raise IdentifierError("identifier length is implausible")
    elif identifier_type == "other":
        v = re.sub(r"\s+", " ", v)       # trim and fold case only; two spellings of an 'other' may not collide
    else:
        raise IdentifierError(f"unknown identifier type {identifier_type!r}")
    return v


def dev_root_key():
    """FIXED, PUBLIC key for seeding and tests. Never use for real data."""
    return hashlib.sha256(b"talentra-dev-only-identifier-root-key").digest()


def root_key(version=CURRENT_VERSION):
    raw = os.getenv(f"TALENTRA_IDENTIFIER_ROOT_KEY_V{version}") or (os.getenv("TALENTRA_IDENTIFIER_ROOT_KEY") if version == CURRENT_VERSION else None)
    if raw is None:
        raise IdentifierError(f"no root key for version {version}: set TALENTRA_IDENTIFIER_ROOT_KEY (64 hex characters)")
    key = bytes.fromhex(raw)
    if len(key) != 32:
        raise IdentifierError("root key must be 32 bytes")
    return key


def _derive(root, label):
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=label).derive(root)


def _aad(organization_id, country_id, identifier_type, version):
    return f"{organization_id}|{country_id}|{identifier_type}|{version}".encode()


def blind_index(identifier_type, canonical, root=None, version=CURRENT_VERSION):
    key = _derive(root or root_key(version), b"talentra/identifier/bidx")
    return hmac.new(key, f"{identifier_type}|{canonical}".encode(), hashlib.sha256).digest()


def encrypt(organization_id, country_id, identifier_type, value, root=None, version=CURRENT_VERSION):
    canonical = canonicalise(identifier_type, value)
    root = root or root_key(version)
    nonce = os.urandom(12)
    ct = AESGCM(_derive(root, b"talentra/identifier/aead")).encrypt(nonce, canonical.encode(), _aad(organization_id, country_id, identifier_type, version))
    return nonce + ct, blind_index(identifier_type, canonical, root, version), version


def decrypt(organization_id, country_id, identifier_type, blob, version=CURRENT_VERSION, root=None):
    root = root or root_key(version)
    blob = bytes(blob)
    return AESGCM(_derive(root, b"talentra/identifier/aead")).decrypt(blob[:12], blob[12:], _aad(organization_id, country_id, identifier_type, version)).decode()


def _selftest():
    root = dev_root_key()
    assert canonicalise("gstin", "27aapfu0939f1zv") == "27AAPFU0939F1ZV"
    try:
        canonicalise("gstin", "27AAPFU0939F1ZW"); raise SystemExit("bad check digit accepted")
    except IdentifierError:
        pass
    for t, v in (("pan", "abcde 1234f"), ("ein", "12 3456789"), ("vat", "gb 123-456-789"), ("other", "  x   y ")):
        c = canonicalise(t, v)
        ct, bidx, ver = encrypt(1, 2, t, v, root)
        assert decrypt(1, 2, t, ct, ver, root) == c and len(bidx) == 32
    ct, _, ver = encrypt(1, 2, "pan", "ABCDE1234F", root)
    try:
        decrypt(9, 2, "pan", ct, ver, root); raise SystemExit("row-swap was not detected")
    except Exception as e:
        if isinstance(e, SystemExit): raise
    print("identifier_crypto self-test passed")


if __name__ == "__main__":
    _selftest()
