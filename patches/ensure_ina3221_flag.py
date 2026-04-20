#!/usr/bin/env python3
"""
Ensure -D ENV_INCLUDE_INA3221=1 is present in the variant platformio.ini.

Used only when sensor_base in the root platformio.ini does NOT already define
ENV_INCLUDE_INA3221 (which is the normal case for newer MeshCore).

Usage: python3 ensure_ina3221_flag.py <variant_platformio.ini>
"""
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

inject = " -D ENV_INCLUDE_INA3221=1\n"
marker = "build_flags = ${nrf52_base.build_flags}"
if "ENV_INCLUDE_INA3221" not in content and marker in content:
    content = content.replace(marker, marker + "\n" + inject, 1)
    with open(path, "w") as f:
        f.write(content)
    print("  Injected ENV_INCLUDE_INA3221 into variant build_flags.")
else:
    print("  ENV_INCLUDE_INA3221 already present — skipping.")
