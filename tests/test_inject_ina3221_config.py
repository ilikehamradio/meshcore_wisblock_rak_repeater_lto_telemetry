#!/usr/bin/env python3
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "patches"))

import inject_ina3221_config as inject  # noqa: E402

RAK4631_INI = """[rak4631]
extends = nrf52_base
board = rak4631
build_flags = ${nrf52_base.build_flags}
  ${sensor_base.build_flags}
  -I variants/rak4631
  -D RAK_4631
"""

RAK3401_INI = """[rak3401]
extends = nrf52_base
board = rak3401
build_flags = ${nrf52_base.build_flags}
  ${sensor_base.build_flags}
  -I variants/rak3401
  -D RAK_3401
"""

LEGACY_INI = """[rak4631]
build_flags = ${nrf52_base.build_flags}
 -D ENV_INCLUDE_RAK12035=1
  -D RAK_4631
"""


class InjectIna3221ConfigTests(unittest.TestCase):
    def test_injects_flags_into_standard_rak4631_ini(self):
        # Arrange
        original = RAK4631_INI

        # Act
        result = inject.inject_ina3221_flags(original)

        # Assert
        self.assertIn("-D TELEM_INA3221_ADDRESS=0x42", result)
        self.assertIn("-D TELEM_INA3221_NUM_CHANNELS=3", result)
        self.assertIn("-D TELEM_INA3221_SHUNT_VALUE=0.100", result)
        self.assertGreater(
            result.find("TELEM_INA3221_ADDRESS"),
            result.find("${sensor_base.build_flags}"),
        )

    def test_injects_flags_into_one_watt_rak3401_ini(self):
        # Arrange
        original = RAK3401_INI

        # Act
        result = inject.inject_ina3221_flags(original)

        # Assert
        self.assertIn("-D TELEM_INA3221_ADDRESS=0x42", result)
        self.assertIn("-D RAK_3401", result)
        self.assertGreater(
            result.find("TELEM_INA3221_ADDRESS"),
            result.find("${sensor_base.build_flags}"),
        )

    def test_is_idempotent_when_flags_already_present(self):
        # Arrange
        already_patched = inject.inject_ina3221_flags(RAK3401_INI)

        # Act
        result = inject.inject_ina3221_flags(already_patched)

        # Assert
        self.assertEqual(already_patched, result)
        self.assertEqual(result.count("TELEM_INA3221_ADDRESS"), 1)

    def test_falls_back_to_legacy_rak12035_anchor(self):
        # Arrange
        original = LEGACY_INI

        # Act
        result = inject.inject_ina3221_flags(original)

        # Assert
        self.assertIn("-D TELEM_INA3221_ADDRESS=0x42", result)
        self.assertGreater(
            result.find("TELEM_INA3221_ADDRESS"),
            result.find("ENV_INCLUDE_RAK12035"),
        )

    def test_raises_when_no_anchor_is_present(self):
        # Arrange
        original = "[rak4631]\nbuild_flags = -D RAK_4631\n"

        # Act
        with self.assertRaises(ValueError) as raised:
            inject.inject_ina3221_flags(original)

        # Assert
        self.assertIn("No insertion anchor found", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
