#!/usr/bin/env python3
"""
Patch LoRa region parameters in the root platformio.ini.

Usage: python3 patch_lora_region.py <root_platformio.ini> <freq_MHz> <bw_kHz> <sf>
  e.g. python3 patch_lora_region.py platformio.ini 910.525 250 11
"""
import re
import sys

path, freq, bw, sf = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(path) as f:
    content = f.read()

content = re.sub(r'(-D LORA_FREQ=)[\d.]+', rf'\g<1>{freq}', content)
content = re.sub(r'(-D LORA_BW=)[\d.]+',   rf'\g<1>{bw}',   content)
content = re.sub(r'(-D LORA_SF=)[\d.]+',   rf'\g<1>{sf}',   content)

with open(path, "w") as f:
    f.write(content)

print(f"  LORA_FREQ={freq}  LORA_BW={bw}  LORA_SF={sf}")
