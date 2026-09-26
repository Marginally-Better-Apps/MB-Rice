#!/usr/bin/env python3
"""Check that two iOS profiles authorize Rice's shared widget container."""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import plistlib
import subprocess
import sys


APP_ID = "app.marginallybetter.rice"
WIDGET_ID = "app.marginallybetter.rice.widgets"
GROUP_ID = "group.app.marginallybetter.rice"


def decode_profile(path: Path) -> dict:
    result = subprocess.run(
        ["security", "cms", "-D", "-i", str(path)],
        check=True,
        capture_output=True,
    )
    return plistlib.loads(result.stdout)


def check_profile(profile: dict, bundle_id: str, device_id: str | None = None) -> list[str]:
    errors = []
    teams = profile.get("TeamIdentifier") or []
    team = teams[0] if teams else None
    entitlements = profile.get("Entitlements") or {}
    expected_app_id = f"{team}.{bundle_id}" if team else None
    actual_app_id = entitlements.get("application-identifier")

    if not team:
        errors.append("missing TeamIdentifier")
    if actual_app_id != expected_app_id:
        errors.append(
            f"application-identifier is {actual_app_id!r}; expected {expected_app_id!r}"
        )
    if GROUP_ID not in entitlements.get("com.apple.security.application-groups", []):
        errors.append(f"missing App Group {GROUP_ID}")

    expiry = profile.get("ExpirationDate")
    if isinstance(expiry, datetime) and expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    if not isinstance(expiry, datetime) or expiry <= datetime.now(timezone.utc):
        errors.append("profile is expired or has no expiration date")

    devices = profile.get("ProvisionedDevices")
    if device_id and devices is not None and device_id not in devices:
        errors.append("this iPhone is not in ProvisionedDevices")
    if not profile.get("ProvisionsAllDevices") and devices is None:
        errors.append("profile cannot be used for direct device installation")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app_profile", type=Path, help="Rice .mobileprovision")
    parser.add_argument("widget_profile", type=Path, help="Rice Widgets .mobileprovision")
    parser.add_argument("--device-id", help="optional iPhone UDID to check")
    args = parser.parse_args()

    profiles = []
    failures = 0
    for label, path, bundle_id in (
        ("Rice", args.app_profile, APP_ID),
        ("Rice Widgets", args.widget_profile, WIDGET_ID),
    ):
        try:
            profile = decode_profile(path)
        except (OSError, subprocess.CalledProcessError, ValueError) as error:
            print(f"{label}: could not read profile: {error}", file=sys.stderr)
            failures += 1
            continue
        profiles.append(profile)
        errors = check_profile(profile, bundle_id, args.device_id)
        print(f"{label}: {profile.get('Name', path.name)}")
        for error in errors:
            print(f"  FAIL: {error}")
        if not errors:
            print("  OK: bundle ID and App Group authorized")
        failures += len(errors)

    if len(profiles) == 2 and profiles[0].get("TeamIdentifier") != profiles[1].get("TeamIdentifier"):
        print("FAIL: Rice and Rice Widgets profiles belong to different teams")
        failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
