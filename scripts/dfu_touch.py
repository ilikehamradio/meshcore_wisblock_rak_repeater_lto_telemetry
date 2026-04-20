#!/usr/bin/env python3
"""
1200 bps "touch" — signals the Adafruit nRF52 bootloader to enter DFU mode.

Usage: python3 dfu_touch.py <serial_port>
  e.g. python3 dfu_touch.py /dev/ttyACM0
"""
import sys
import time

try:
    import serial
except ImportError:
    print("  Error: pyserial not installed (pip install pyserial).")
    sys.exit(1)

port = sys.argv[1]
try:
    s = serial.Serial(port, 1200, timeout=1)
    time.sleep(0.1)
    s.close()
    time.sleep(0.1)
    print("  Touch sent.")
except Exception as e:
    # Device may already be in DFU mode (no CDC serial to open)
    print(f"  Touch skipped ({e}) — device may already be in DFU mode.")
