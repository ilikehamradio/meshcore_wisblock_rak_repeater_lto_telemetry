#!/usr/bin/env python3
"""
Inject Voltaic MCSBC-SVR INA3221 build flags into a WisBlock variant
platformio.ini (RAK4631 or RAK3401).

Hardware: RAK4631 or RAK3401 core on RAK19007 base board.
I2C bus: Wire on pins 13 (SDA) / 14 (SCL) — the standard WisBlock I2C bus.
INA3221 address: 0x42 (confirmed by Voltaic Enclosures documentation).
Shunt: 0.1 ohm (Voltaic MCSBC-SVR).

EnvironmentSensorManager.cpp wraps every value in #ifndef guards so these
build flags override safely without touching C++ source.

Usage: python3 inject_ina3221_config.py <variant/platformio.ini>
"""
import sys

INA3221_FLAGS = (
    "  -D TELEM_INA3221_ADDRESS=0x42\n"       # Voltaic MCSBC-SVR (confirmed in Voltaic docs)
    "  -D TELEM_INA3221_NUM_CHANNELS=3\n"     # solar, battery, load
    "  -D TELEM_INA3221_SHUNT_VALUE=0.100\n"  # 0.1 ohm shunts
)

# Prefer the shared sensor_base include (current MeshCore). Fall back to the
# older per-variant ENV_INCLUDE_RAK12035 flag used by earlier MeshCore trees.
INSERT_ANCHORS = (
    "  ${sensor_base.build_flags}\n",
    " -D ENV_INCLUDE_RAK12035=1\n",
    "  -D ENV_INCLUDE_RAK12035=1\n",
)


def inject_ina3221_flags(content):
    """Return platformio.ini text with INA3221 telemetry flags inserted.

    Raises ValueError if no known insertion anchor is present.
    """
    if "TELEM_INA3221_ADDRESS" in content:
        return content
    for anchor in INSERT_ANCHORS:
        if anchor in content:
            return content.replace(anchor, anchor + INA3221_FLAGS, 1)
    raise ValueError(
        "No insertion anchor found. Expected ${sensor_base.build_flags} "
        "or ENV_INCLUDE_RAK12035 in the variant platformio.ini."
    )


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("Usage: inject_ina3221_config.py <variant/platformio.ini>\n")
        return 2
    path = argv[1]
    with open(path) as f:
        content = f.read()
    if "TELEM_INA3221_ADDRESS" in content:
        print("  INA3221 flags already present — skipping.")
        return 0
    try:
        updated = inject_ina3221_flags(content)
    except ValueError as exc:
        print("  Error: %s" % exc)
        return 1
    with open(path, "w") as f:
        f.write(updated)
    print("  TELEM_INA3221_ADDRESS  = 0x42  (Voltaic MCSBC-SVR, confirmed)")
    print("  TELEM_INA3221_NUM_CHANNELS = 3  (solar / battery / load)")
    print("  TELEM_INA3221_SHUNT_VALUE  = 0.100 ohm")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
