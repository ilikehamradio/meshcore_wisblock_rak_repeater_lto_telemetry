#!/usr/bin/env python3
"""
Inject Voltaic MCSBC-SVR INA3221 build flags into the [rak4631] section of
variants/rak4631/platformio.ini.

Hardware: RAK4631 core on RAK19007 base board.
I2C bus: Wire on pins 13 (SDA) / 14 (SCL) — the standard WisBlock I2C bus.
INA3221 address: 0x42 (confirmed by Voltaic Enclosures documentation).
Shunt: 0.1 ohm (Voltaic MCSBC-SVR).

EnvironmentSensorManager.cpp wraps every value in #ifndef guards so these
build flags override safely without touching C++ source.

Usage: python3 inject_ina3221_config.py <variants/rak4631/platformio.ini>
"""
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

flags = (
    " -D TELEM_INA3221_ADDRESS=0x42\n"       # Voltaic MCSBC-SVR (confirmed in Voltaic docs)
    " -D TELEM_INA3221_NUM_CHANNELS=3\n"     # solar, battery, load
    " -D TELEM_INA3221_SHUNT_VALUE=0.100\n"  # 0.1 ohm shunts
)

# Anchor: the last build flag in the [rak4631] base section.
anchor = " -D ENV_INCLUDE_RAK12035=1\n"

if "TELEM_INA3221_ADDRESS" not in content:
    if anchor not in content:
        print(f"  Error: anchor '{anchor.strip()}' not found in {path}.")
        sys.exit(1)
    content = content.replace(anchor, anchor + flags, 1)
    with open(path, "w") as f:
        f.write(content)
    print("  TELEM_INA3221_ADDRESS  = 0x42  (Voltaic MCSBC-SVR, confirmed)")
    print("  TELEM_INA3221_NUM_CHANNELS = 3  (solar / battery / load)")
    print("  TELEM_INA3221_SHUNT_VALUE  = 0.100 ohm")
else:
    print("  INA3221 flags already present — skipping.")
