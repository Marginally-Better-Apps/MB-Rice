import unittest
from datetime import datetime, timedelta, timezone

from tools.check_widget_profiles import APP_ID, GROUP_ID, WIDGET_ID, check_profile


class ProfileCheckTests(unittest.TestCase):
    def profile(self, bundle_id: str) -> dict:
        return {
            "TeamIdentifier": ["TEAM123"],
            "Entitlements": {
                "application-identifier": f"TEAM123.{bundle_id}",
                "com.apple.security.application-groups": [GROUP_ID],
            },
            "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=30),
            "ProvisionedDevices": ["PHONE123"],
        }

    def test_explicit_app_and_widget_profiles_pass(self):
        self.assertEqual(check_profile(self.profile(APP_ID), APP_ID, "PHONE123"), [])
        self.assertEqual(check_profile(self.profile(WIDGET_ID), WIDGET_ID, "PHONE123"), [])

    def test_wildcard_profile_cannot_authorize_rice_app_group(self):
        profile = self.profile(APP_ID)
        profile["Entitlements"]["application-identifier"] = "TEAM123.*"
        profile["Entitlements"].pop("com.apple.security.application-groups")
        errors = check_profile(profile, APP_ID)
        self.assertTrue(any("application-identifier" in error for error in errors))
        self.assertTrue(any("missing App Group" in error for error in errors))

    def test_wrong_device_or_expired_profile_fails(self):
        profile = self.profile(WIDGET_ID)
        profile["ExpirationDate"] = datetime.now(timezone.utc) - timedelta(days=1)
        errors = check_profile(profile, WIDGET_ID, "OTHERPHONE")
        self.assertTrue(any("expired" in error for error in errors))
        self.assertTrue(any("ProvisionedDevices" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
