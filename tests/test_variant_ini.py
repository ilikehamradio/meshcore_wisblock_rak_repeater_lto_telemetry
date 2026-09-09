#!/usr/bin/env python3
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import variant_ini  # noqa: E402


class VariantIniTests(unittest.TestCase):
    def test_maps_standard_repeater_env_to_rak4631(self):
        # Arrange
        env_name = "RAK_4631_repeater"

        # Act
        path = variant_ini.variant_ini_for_env(env_name)

        # Assert
        self.assertEqual(path, "variants/rak4631/platformio.ini")

    def test_maps_one_watt_repeater_env_to_rak3401(self):
        # Arrange
        env_name = "RAK_3401_repeater"

        # Act
        path = variant_ini.variant_ini_for_env(env_name)

        # Assert
        self.assertEqual(path, "variants/rak3401/platformio.ini")

    def test_maps_other_envs_in_the_same_family(self):
        # Arrange
        cases = (
            ("RAK_4631_room_server", "variants/rak4631/platformio.ini"),
            ("RAK_3401_companion_radio_ble", "variants/rak3401/platformio.ini"),
        )

        for env_name, expected in cases:
            # Act
            path = variant_ini.variant_ini_for_env(env_name)

            # Assert
            self.assertEqual(path, expected, env_name)

    def test_rejects_unsupported_environments(self):
        # Arrange
        env_name = "Heltec_v3_repeater"

        # Act
        with self.assertRaises(ValueError) as raised:
            variant_ini.variant_ini_for_env(env_name)

        # Assert
        self.assertIn("Unsupported MeshCore environment", str(raised.exception))

    def test_rejects_empty_environment(self):
        # Arrange
        env_name = ""

        # Act
        with self.assertRaises(ValueError) as raised:
            variant_ini.variant_ini_for_env(env_name)

        # Assert
        self.assertIn("ENV_NAME is empty", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
