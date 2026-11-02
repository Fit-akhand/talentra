#!/usr/bin/env python3
"""Tests of the application-side identifier protection (scripts/identifier_crypto.py): canonical forms, AEAD, blind index, key separation."""
# Covers: BR-037   (generated from the registers by scripts/lifecycle/tag_tests.py)
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import identifier_crypto as ic

fails = []
def check(name, cond):
    print(("PASS: " if cond else "FAIL: ") + name)
    if not cond: fails.append(name)

root = ic.dev_root_key()
check("GSTIN canonical form ignores case and separators", ic.canonicalise("gstin", "27-aapfu0939f1zv") == "27AAPFU0939F1ZV")
for bad in ("27AAPFU0939F1ZW", "XYZ", ""):
    try: ic.canonicalise("gstin", bad); ok = False
    except ic.IdentifierError: ok = True
    check(f"GSTIN {bad!r} rejected, not repaired", ok)
check("EIN formatted to NN-NNNNNNN", ic.canonicalise("ein", "123456789") == "12-3456789")
ct1, b1, v = ic.encrypt(1, 2, "pan", "ABCDE1234F", root)
ct2, b2, _ = ic.encrypt(1, 2, "pan", "abcde 1234f", root)
check("same identifier, different spelling: same blind index", b1 == b2)
check("same identifier twice: different ciphertext (random nonce)", ct1 != ct2)
check("round trip", ic.decrypt(1, 2, "pan", ct1, v, root) == "ABCDE1234F")
check("plaintext is not inside the ciphertext", b"ABCDE1234F" not in ct1)
for label, args in (("organisation", (9, 2, "pan")), ("country", (1, 9, "pan")), ("type", (1, 2, "cin"))):
    try: ic.decrypt(*args, ct1, v, root); ok = False
    except Exception: ok = True
    check(f"ciphertext moved to another {label} fails to decrypt", ok)
tampered = bytearray(ct1); tampered[-1] ^= 1
try: ic.decrypt(1, 2, "pan", bytes(tampered), v, root); ok = False
except Exception: ok = True
check("tampered ciphertext detected", ok)
other = bytes(32)
check("a different root key gives a different blind index", ic.blind_index("pan", "ABCDE1234F", other) != b1)
check("blind index depends on identifier type", ic.blind_index("pan", "ABCDE1234F", root) != ic.blind_index("other", "ABCDE1234F", root))
sys.exit(1 if fails else 0)
