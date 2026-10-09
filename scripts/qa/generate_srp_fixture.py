#!/usr/bin/env python3
"""Independent deterministic test-only vector; never accepts real credentials."""
import hashlib
import json
import re
import urllib.request


def fixture():
    with urllib.request.urlopen("https://www.rfc-editor.org/rfc/rfc5054.txt", timeout=15) as response:
        text = response.read().decode("ascii")
    section = text.split("5.  4096-bit Group", 1)[1].split("The generator is:", 1)[0]
    prime = "".join("".join(line.split()) for line in section.splitlines()
                    if re.fullmatch(r"\s+[0-9A-F ]+", line))
    if len(prime) != 1024:
        raise ValueError("RFC group extraction failed")
    n, g = int(prime, 16), 5
    pad = lambda value: value.to_bytes(512, "big")
    digest = lambda data: hashlib.sha512(data).digest()
    salt = bytes(range(32))
    a = int.from_bytes(bytes(range(1, 33)), "big")
    b = int.from_bytes(bytes(range(33, 65)), "big")
    password = hashlib.pbkdf2_hmac("sha512", b"fixture-password", salt, 10, 128)
    x = int.from_bytes(digest(salt + digest(b":" + password)), "big")
    k = int.from_bytes(digest(pad(n) + pad(g)), "big")
    verifier = pow(g, x, n)
    server_public = (k * verifier + pow(g, b, n)) % n
    client_public = pow(g, a, n)
    u = int.from_bytes(digest(pad(client_public) + pad(server_public)), "big")
    client_secret = pow((server_public - k * verifier) % n, a + u * x, n)
    server_secret = pow((client_public * pow(verifier, u, n)) % n, b, n)
    if client_secret != server_secret:
        raise ValueError("Independent client/server shared secrets differ")
    key = digest(pad(client_secret))
    mixed = bytes(left ^ right for left, right in zip(digest(pad(n)), digest(bytes([g]))))
    m1 = digest(mixed + digest(b"") + salt + pad(client_public) + pad(server_public) + key)
    m2 = digest(pad(client_public) + m1 + key)
    padded_mixed = bytes(left ^ right for left, right in zip(digest(pad(n)), digest(pad(g))))
    padded_m1 = digest(padded_mixed + digest(b"") + salt + pad(client_public) + pad(server_public) + key)
    padded_m2 = digest(pad(client_public) + padded_m1 + key)
    return {"N": prime, "salt": salt.hex(), "a": a.to_bytes(32, "big").hex(),
            "B": pad(server_public).hex(), "A": pad(client_public).hex(),
            "M1": m1.hex(), "M2": m2.hex(),
            "paddedM1": padded_m1.hex(), "paddedM2": padded_m2.hex(),
            "wrap": hashlib.sha256(key).digest()[:16].hex()}


if __name__ == "__main__":
    print(json.dumps(fixture(), sort_keys=True))
