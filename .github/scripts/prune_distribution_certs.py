#!/usr/bin/env python3
"""Prune stale Xcode-managed distribution certificates.

Why this exists: every CI runner is a blank macOS VM with an empty
keychain, so `xcodebuild -allowProvisioningUpdates` mints a fresh key
pair and a fresh "Xcode Managed Distribution" certificate on every
run. Apple's account-wide cap on distribution certificates fills up
after a handful of TestFlight uploads and the archive dies with
"Your account has reached the maximum number of certificates".

This script talks to the App Store Connect API with the same key the
signing itself uses, and revokes every Xcode-managed distribution
certificate except the newest one — the garbage from previous runs,
never a certificate created by hand. Revocation is safe for anything
already shipped: uploaded TestFlight builds stay signed and installed
apps are untouched; only future archives would have used those certs,
and the next archive mints (or reuses) a fresh one anyway.

Called from testflight.yml as:
    prune_distribution_certs.py /path/to/AuthKey.p8
with ASC_KEY_ID and ASC_ISSUER_ID in the environment. Requires the
pyjwt and cryptography packages (the workflow installs them into a
throwaway venv).
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
# How the cloud's own minted certificates name themselves: Xcode's
# older label, and the App Store Connect API's "Created via API" mark
# the current toolchain stamps on distribution certs CI asks for.
# Hand-made certificates carry the portal's "Team Name (Team ID)"
# label instead and never match — they are never revoked here.
MANAGED_NAMES = {"Xcode Managed Distribution"}
API_CREATED_MARK = "Created via API"
DISTRIBUTION_TYPES = {"APPLE_DISTRIBUTION", "IOS_DISTRIBUTION", "DISTRIBUTION"}
# Keep this many newest managed certificates; everything older goes.
KEEP = 1


def main() -> None:
    with open(sys.argv[1]) as f:
        private_key = f.read()
    now = int(time.time())
    token = jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )

    def api(method: str, path: str):
        request = urllib.request.Request(
            API + path,
            method=method,
            headers={"Authorization": "Bearer " + token},
        )
        try:
            with urllib.request.urlopen(request) as response:
                if response.status == 204:
                    return None
                return json.load(response)
        except urllib.error.HTTPError as error:
            print(f"{method} {path} -> {error.code}", file=sys.stderr)
            print(error.read().decode(), file=sys.stderr)
            raise

    certificates = api("GET", "/certificates?limit=200")["data"]
    managed = [
        c for c in certificates
        if c["attributes"].get("certificateType") in DISTRIBUTION_TYPES
        and (
            c["attributes"].get("name") in MANAGED_NAMES
            or API_CREATED_MARK in c["attributes"].get("name", "")
        )
    ]
    all_types = {}
    for c in certificates:
        key = (c["attributes"].get("name"), c["attributes"].get("certificateType"))
        all_types[key] = all_types.get(key, 0) + 1
    for key, count in sorted(all_types.items(), key=str):
        print(f"  {count}x {key[0]!r} ({key[1]})")
    # Newest expiration first — the freshest KEEP survive.
    managed.sort(key=lambda c: c["attributes"].get("expirationDate", ""), reverse=True)
    for cert in managed[KEEP:]:
        attributes = cert["attributes"]
        print(
            "revoking stale certificate "
            f"serial={attributes.get('serialNumber')} "
            f"expires={attributes.get('expirationDate')}"
        )
        api("DELETE", "/certificates/" + cert["id"])
    print(
        f"managed distribution certificates: {len(managed)} found, "
        f"{min(len(managed), KEEP)} kept, {max(0, len(managed) - KEEP)} revoked"
    )


if __name__ == "__main__":
    main()
