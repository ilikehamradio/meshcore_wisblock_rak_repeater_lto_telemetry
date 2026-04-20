#!/usr/bin/env bash
# Runs INSIDE the flash container with --privileged -v /dev:/dev so it sees
# the host's /dev tree in real time and can watch the board re-enumerate
# after the 1200 bps DFU touch.
#
# Expected bind mounts from host:
#   /scripts   (ro)  — this file + dfu_touch.py
#   /firmware  (ro)  — folder containing firmware.zip
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DFU_PKG="/firmware/firmware.zip"

if [ ! -f "$DFU_PKG" ]; then
    echo -e "${RED}Error: DFU package not found at ${DFU_PKG}${NC}"
    exit 1
fi

# ---- Port selection (inside container, same /dev as host) ------------------
FLASH_PORT="${FLASH_PORT:-}"

if [ -z "$FLASH_PORT" ]; then
    echo "Scanning for serial ports..."
    PORTS=()
    for p in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$p" ] && PORTS+=("$p")
    done

    if [ ${#PORTS[@]} -eq 0 ]; then
        echo -e "${RED}No serial ports found. Is the device plugged in?${NC}"
        exit 1
    elif [ ${#PORTS[@]} -eq 1 ]; then
        FLASH_PORT="${PORTS[0]}"
        echo -e "  Auto-selected: ${GREEN}${FLASH_PORT}${NC}"
    else
        echo "  Multiple ports detected:"
        for i in "${!PORTS[@]}"; do
            echo "    $((i+1))) ${PORTS[$i]}"
        done
        read -rp "  Select port [1-${#PORTS[@]}]: " PICK
        FLASH_PORT="${PORTS[$((PICK - 1))]}"
    fi
fi

echo -e "  Port   : ${GREEN}${FLASH_PORT}${NC}"
echo -e "  Package: ${DFU_PKG}"
echo

# ---- Snapshot ports before the touch so we can detect re-enumeration -------
BEFORE_PORTS=()
for p in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$p" ] && BEFORE_PORTS+=("$p")
done

# ---- 1200 bps touch — signals Adafruit bootloader to enter DFU mode --------
echo -e "${YELLOW}Triggering DFU mode via 1200 bps touch...${NC}"
# pyserial is installed in the container alongside adafruit-nrfutil.
python3 /scripts/dfu_touch.py "$FLASH_PORT"

# ---- Wait for device to reboot and re-enumerate ----------------------------
echo -e "${YELLOW}Waiting for device to re-enumerate (up to 15 s)...${NC}"
DFU_PORT=""
for _ in $(seq 1 15); do
    sleep 1
    # Look for a brand-new port that wasn't present before the touch
    for p in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$p" ] || continue
        is_new=1
        for old in "${BEFORE_PORTS[@]+"${BEFORE_PORTS[@]}"}"; do
            [[ "$p" == "$old" ]] && is_new=0 && break
        done
        if [ "$is_new" -eq 1 ]; then
            DFU_PORT="$p"
            break 2
        fi
    done
    # On Linux the nRF52 bootloader usually comes back on the same ttyACM node
    [ -e "$FLASH_PORT" ] && DFU_PORT="$FLASH_PORT" && break
done

if [ -z "$DFU_PORT" ]; then
    echo -e "${RED}Device did not re-enumerate within 15 seconds.${NC}"
    echo "  Make sure the device is running MeshCore firmware and is not"
    echo "  already stuck in an unexpected state."
    exit 1
fi
echo -e "  Device ready on ${GREEN}${DFU_PORT}${NC}"

# ---- Flash -----------------------------------------------------------------
echo
echo -e "${YELLOW}Flashing firmware...${NC}"
# --singlebank matches PlatformIO's own nrfutil upload invocation for nRF52
adafruit-nrfutil dfu serial \
    --package   "$DFU_PKG" \
    --port      "$DFU_PORT" \
    --baudrate  115200 \
    --singlebank

echo
echo -e "${GREEN}Flash complete!${NC}"
