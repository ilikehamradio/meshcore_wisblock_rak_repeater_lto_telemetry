#!/usr/bin/env python3
"""
Patch for src/helpers/sensors/EnvironmentSensorManager.cpp.

  Step 1: Force-enable channels 0/1/2 after begin(). The INA3221 chip can
          power up with only channel 0 active; this ensures all three are on.

  Step 2: Remove the isChannelEnabled(i) guard. On nRF52 the library re-reads
          the INA3221 config register on every call and can silently NAK,
          returning false for channels 1 and 2 even though they were enabled
          in Step 1 — the root cause of only one channel appearing in telemetry.

  Step 3: Add a MESH_DEBUG_PRINTLN per channel so V/A/W values are visible on
          serial when -D MESH_DEBUG=1. Compiles out completely in production.

Usage: python3 patch_env_sensor_manager.py <EnvironmentSensorManager.cpp>
"""
import re, sys

path = sys.argv[1]
try:
    with open(path) as f:
        content = f.read()
except FileNotFoundError:
    print(f"  Warning: {path} not found — skipping source patch.")
    sys.exit(0)

# ── Step 1: force-enable all 3 channels right after begin() ──────────────────
enable_pat = r'([ \t]*)(INA3221_initialized = true;)'
enable_rep = (
    r'\1INA3221.enableChannel(0); // force-enable all 3 channels\n'
    r'\1INA3221.enableChannel(1);\n'
    r'\1INA3221.enableChannel(2);\n'
    r'\1\2'
)
content, n1 = re.subn(enable_pat, enable_rep, content)
print(f"  Step 1: {'added enableChannel(0/1/2).' if n1 else 'INA3221_initialized not found — skipped.'}")

# ── Step 2: remove isChannelEnabled() guard ──────────────────────────────────
guard_pat = r'([ \t]*)if \(INA3221\.isChannelEnabled\(i\)\) \{'
guard_rep = r'\1{ // isChannelEnabled guard removed (unreliable on nRF52)'
content, n2 = re.subn(guard_pat, guard_rep, content)
print(f"  Step 2: {'removed isChannelEnabled guard.' if n2 else 'guard not found — skipped.'}")

# ── Step 3: add MESH_DEBUG_PRINTLN per channel ───────────────────────────────
debug_pat = r'([ \t]*)(telemetry\.addVoltage\(next_available_channel, voltage\);)'
debug_rep = (
    r'\1MESH_DEBUG_PRINTLN("INA3221 ch%d: %.3fV  %.3fA  %.3fW",'
    r' i, voltage, current, voltage*current);\n'
    r'\1\2'
)
content, n3 = re.subn(debug_pat, debug_rep, content)
print(f"  Step 3: {'added per-channel debug print.' if n3 else 'addVoltage not found — skipped.'}")

with open(path, "w") as f:
    f.write(content)
