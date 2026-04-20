#!/usr/bin/env bash
# Runs INSIDE the build container. Bind-mounted from host scripts/ so edits
# take effect on the next run without rebuilding the Docker image.
#
# MeshCore source is cloned fresh every invocation and all patches are
# re-applied, so running this script is always a clean-slate build.
#
# Expected bind mounts from host:
#   /scripts  (ro)  — this file + sibling helpers
#   /patches  (ro)  — patch scripts (patches/*.py)
#   /output   (rw)  — firmware artifacts are copied here
#
# Expected env vars: ENV_NAME, LORA_FREQ, LORA_BW, LORA_SF,
#                    MESHCORE_COMMIT (optional)
set -euo pipefail

MESHCORE_REPO="https://github.com/meshcore-dev/MeshCore.git"
BUILD_DIR="/tmp/meshcore_build"
PATCHES="/patches"

# Wipe any stale build tree from a previous container (shouldn't happen with
# --rm but belt and suspenders — guarantees source is fresh every invocation).
rm -rf "$BUILD_DIR"

# Resolve the commit to build
if [ -z "${MESHCORE_COMMIT:-}" ]; then
    echo "Fetching latest MeshCore commit hash..."
    MESHCORE_COMMIT=$(git ls-remote "$MESHCORE_REPO" refs/heads/main | cut -f1)
    echo "  Latest commit: $MESHCORE_COMMIT"
else
    echo "  Pinned commit: $MESHCORE_COMMIT"
fi

echo "Cloning MeshCore (fresh source every run)..."
git clone --depth=1 "$MESHCORE_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"
# If a specific (non-latest) commit was requested, do a full fetch + checkout
if ! git cat-file -e "${MESHCORE_COMMIT}^{commit}" 2>/dev/null; then
    git fetch --unshallow
fi
git checkout --detach "$MESHCORE_COMMIT"
echo "  Checked out: $(git log -1 --format='%h %s')"

ROOT_INI="platformio.ini"
VARIANT_INI="variants/rak4631/platformio.ini"

for ini in "$ROOT_INI" "$VARIANT_INI"; do
    if [ ! -f "$ini" ]; then
        echo "Error: expected file not found: $ini"
        exit 1
    fi
done

# ── Apply patches (always re-applied — working tree is a fresh clone) ───────
if grep -q "ENV_INCLUDE_INA3221" "$ROOT_INI"; then
    echo "  ENV_INCLUDE_INA3221: confirmed present in sensor_base"
else
    echo "  ENV_INCLUDE_INA3221 not found in sensor_base — injecting into variant ini..."
    python3 "$PATCHES/ensure_ina3221_flag.py" "$VARIANT_INI"
fi

echo "Patching LoRa region in platformio.ini..."
python3 "$PATCHES/patch_lora_region.py" "$ROOT_INI" "$LORA_FREQ" "$LORA_BW" "$LORA_SF"

echo "Applying Voltaic Xpander INA3221 patches..."
python3 "$PATCHES/inject_ina3221_config.py" "$VARIANT_INI"

ENV_SENSOR_CPP="src/helpers/sensors/EnvironmentSensorManager.cpp"
echo "Patching ${ENV_SENSOR_CPP} (3-step INA3221 fix)..."
python3 "$PATCHES/patch_env_sensor_manager.py" "$ENV_SENSOR_CPP"

# ── Build ────────────────────────────────────────────────────────────────────
echo
echo "Building '${ENV_NAME}' (first run downloads ~500 MB of toolchain)..."
# For rak4631 (nrfutil upload protocol) PlatformIO produces firmware.zip
# (DFU package) as the primary target and firmware.hex as an intermediate.
pio run -e "$ENV_NAME"

BUILD_OUT=".pio/build/${ENV_NAME}"

echo
echo "Generating UF2 file..."
# The create-uf2.py extra_script registers a separate custom target — it is
# NOT run automatically by 'pio run', so we invoke it explicitly here.
pio run -e "$ENV_NAME" -t create_uf2 || echo "  Warning: UF2 generation failed (non-fatal)."

echo
echo "Build artifacts:"
ls -lh "$BUILD_OUT"/ 2>/dev/null | tail -n +2

# Copy firmware artifacts to the bind-mounted /output directory.
# firmware.zip  — DFU package for adafruit-nrfutil serial flashing
# firmware.hex  — intermediate hex (also usable with nrfjprog / J-Link)
# firmware.uf2  — UF2 for drag-and-drop via the RAK4631 bootloader drive
COPIED=0
for f in firmware.zip firmware.hex firmware.uf2; do
    src="${BUILD_OUT}/${f}"
    if [ -f "$src" ]; then
        cp -v "$src" "/output/${f}"
        COPIED=$((COPIED + 1))
    fi
done

if [ "$COPIED" -eq 0 ]; then
    echo "Error: no firmware artifacts found in ${BUILD_OUT}/"
    exit 1
fi
