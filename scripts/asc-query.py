#!/usr/bin/env python3
"""
asc-query.py — Inspect TestFlight / App Store Connect state for Forge Commander.

Mints an ES256 JWT from the App Store Connect API key (.p8) and queries the
ASC REST API. Use this to diagnose "build uploaded but not showing on device"
(see ios-testflight-headless-deploy-sop.md §6.1 / §6.2). The deploy itself uses
`altool` which mints its own token — this is the read/inspect companion.

Auth: same key the deploy script uses (App Manager role is sufficient for reads).
  Key file:  ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8  (chmod 600)
  Key ID / Issuer ID are NOT secret (set below); the .p8 is the secret.

Requires: python3 with the `cryptography` package (no PyJWT needed).

Usage:
  ./scripts/asc-query.py builds            # all builds, newest first (processingState)
  ./scripts/asc-query.py state             # latest build's internal/external beta state
  ./scripts/asc-query.py group             # "Field Devices" group: its builds + testers
  ./scripts/asc-query.py testers           # group testers + their state (INVITED/INSTALLED)
  ./scripts/asc-query.py resend            # resend the TestFlight invite (forcing function, §6.1)
  ./scripts/asc-query.py token             # just print a fresh JWT (for ad-hoc curl)
"""
import json
import sys
import time
import base64
import urllib.request
import urllib.error

# ---- Config (non-secret identifiers; the .p8 is the secret) -----------------
KEY_ID = "ZU87A99896"
ISSUER = "69a6de97-90d1-47e3-e053-5b8c7c11a4d1"
KEY_PATH = "/Users/devops/.appstoreconnect/private_keys/AuthKey_ZU87A99896.p8"

APP_ID = "6781540528"                                  # Forge Commander
GROUP_ID = "0b63f747-36ca-4859-8137-35b6f5acef61"      # "Field Devices" internal group
TESTER_ID = "0bcde981-54a0-49e4-908f-c23f4638a427"     # daniel@willitzer.com

API = "https://api.appstoreconnect.apple.com"


def _b64url(b: bytes) -> bytes:
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def mint_token() -> str:
    """ES256 JWT, 20-min expiry, aud=appstoreconnect-v1."""
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    with open(KEY_PATH, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)

    now = int(time.time())
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + b"."
        + _b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return (signing_input + b"." + _b64url(raw)).decode()


def _req(method: str, path: str, token: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        return e.code, (json.loads(raw) if raw else {})


def _print(status: int, payload: dict) -> None:
    print(f"HTTP {status}")
    print(json.dumps(payload, indent=2))


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    token = mint_token()

    if cmd == "token":
        print(token)
        return 0

    if cmd == "builds":
        _print(*_req("GET", (
            f"/v1/builds?filter[app]={APP_ID}"
            "&fields[builds]=version,processingState,uploadedDate,expired,minOsVersion"
            "&sort=-version&limit=10"), token))
    elif cmd == "state":
        st, blds = _req("GET", f"/v1/builds?filter[app]={APP_ID}&sort=-version&limit=1", token)
        if st != 200 or not blds.get("data"):
            return _print(st, blds) or 1
        bid = blds["data"][0]["id"]
        _print(*_req("GET", (
            f"/v1/builds/{bid}/buildBetaDetail"
            "?fields[buildBetaDetails]=internalBuildState,externalBuildState,autoNotifyEnabled"), token))
    elif cmd == "group":
        print("=== group builds ===")
        _print(*_req("GET", (
            f"/v1/betaGroups/{GROUP_ID}/builds"
            "?fields[builds]=version,processingState&limit=10"), token))
        print("\n=== group testers ===")
        _print(*_req("GET", (
            f"/v1/betaGroups/{GROUP_ID}/betaTesters"
            "?fields[betaTesters]=email,firstName,lastName,state&limit=50"), token))
    elif cmd == "testers":
        _print(*_req("GET", (
            f"/v1/betaGroups/{GROUP_ID}/betaTesters"
            "?fields[betaTesters]=email,firstName,lastName,inviteType,state&limit=50"), token))
    elif cmd == "resend":
        # The forcing function for "build in group but not showing on device" (§6.1).
        body = {"data": {"type": "betaTesterInvitations", "relationships": {
            "app": {"data": {"type": "apps", "id": APP_ID}},
            "betaTester": {"data": {"type": "betaTesters", "id": TESTER_ID}}}}}
        st, payload = _req("POST", "/v1/betaTesterInvitations", token, body)
        _print(st, payload)
        if st == 201:
            print("\n→ Invite sent. On device: open the TestFlight email → "
                  "'View in TestFlight' → Install.")
        return 0 if st == 201 else 1
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
