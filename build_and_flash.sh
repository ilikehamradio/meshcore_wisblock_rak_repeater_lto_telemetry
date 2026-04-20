#!/usr/bin/env bash
# Build MeshCore firmware for RAK WisBlock (RAK4631 / nRF52840) in Docker
# and flash to the device via DFU serial, J-Link, or UF2.
#
# ENV_INCLUDE_INA3221=1 is enabled via sensor_base (confirmed at build time).
#
# Usage: ./build_and_flash.sh [--commit <COMMIT>] [--env <ENV_NAME>]
#   --commit  Pin to a specific MeshCore git commit (default: latest main)
#   --env     PlatformIO environment to build   (default: RAK_4631_repeater)
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

IMAGE_TAG="meshcore-rak-builder:latest"
DOCKER_CTX="/tmp/meshcore_rak_docker_$$"
ORIGINAL_PWD="$PWD"
# Resolve the directory this script lives in so patches/ and scripts/ can be
# located regardless of the caller's cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"
HOST_SCRIPTS_DIR="$SCRIPT_DIR/scripts"
MESHCORE_COMMIT=""
ENV_NAME="RAK_4631_repeater"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit|-c)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --commit requires a value.${NC}"
                exit 1
            fi
            MESHCORE_COMMIT="$2"
            shift 2
            ;;
        --env|-e)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --env requires a value.${NC}"
                exit 1
            fi
            ENV_NAME="$2"
            shift 2
            ;;
        --rebuild|-r)
            echo -e "${YELLOW}--rebuild: image is always rebuilt fresh — flag is now a no-op.${NC}"
            shift
            ;;
        -h|--help)
            head -n 10 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--commit COMMIT] [--env ENV_NAME]"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
cleanup() {
    rm -rf "$DOCKER_CTX"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Error: docker is required but not installed.${NC}"
        echo "  Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker daemon is not running or you lack permission.${NC}"
        echo "  Try:  sudo systemctl start docker"
        echo "  Or:   sudo usermod -aG docker \$USER  (then log out and back in)"
        exit 1
    fi
}

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MeshCore RAK WisBlock Firmware Builder      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo
echo -e "  Target environment : ${CYAN}${ENV_NAME}${NC}"
echo -e "  INA3221 support    : ${GREEN}enabled (via sensor_base)${NC}"
echo -e "  Every run is a clean slate (firmware, Docker image, and caches purged first)."
echo

check_docker

# ---------------------------------------------------------------------------
# Nuke all stale artifacts and caches — guaranteed virgin state every run
# Only touches things created by THIS script; other Docker images/containers
# and build caches are left completely alone.
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Purging stale firmware, Docker image, and Python cache...${NC}"

# Firmware artifacts from prior runs
for f in firmware.zip firmware.hex firmware.uf2; do
    rm -f "${SCRIPT_DIR}/${f}" && echo -e "  ${GREEN}removed${NC} ${f}" || true
done

# Only remove OUR image (identified by its exact tag)
if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    # Stop and remove any containers running OUR image before removing the image
    our_containers=$(docker ps -aq --filter "ancestor=${IMAGE_TAG}" 2>/dev/null || true)
    if [ -n "$our_containers" ]; then
        docker rm -f $our_containers >/dev/null 2>&1 || true
        echo -e "  ${GREEN}removed${NC} stopped containers for ${IMAGE_TAG}"
    fi
    docker rmi -f "$IMAGE_TAG" >/dev/null 2>&1 \
        && echo -e "  ${GREEN}removed${NC} Docker image: ${IMAGE_TAG}" \
        || echo -e "  ${RED}failed to remove${NC} Docker image: ${IMAGE_TAG}"
fi
# NOTE: intentionally NOT running docker builder prune or docker container prune
#       as those would affect the user's other projects.

# Python __pycache__ in patches/ and scripts/ only
find "${PATCHES_DIR}" "${HOST_SCRIPTS_DIR}" -type d -name '__pycache__' \
    -exec rm -rf {} + 2>/dev/null || true
find "${PATCHES_DIR}" "${HOST_SCRIPTS_DIR}" -name '*.pyc' \
    -delete 2>/dev/null || true
echo -e "  ${GREEN}removed${NC} Python __pycache__"
echo

# ---------------------------------------------------------------------------
# Region selection
# ---------------------------------------------------------------------------
echo "Select your LoRa region:"
echo "  1) USA / Canada                (910.525 MHz)"
echo "  2) USA / Canada (alternate 1)  (907.875 MHz)"
echo "  3) USA / Canada (alternate 2)  (927.875 MHz)"
echo "  4) Europe / UK                 (869.525 MHz)"
echo "  5) Europe (alternate)          (868.731 MHz)"
echo "  6) Australia / New Zealand     (915.8 MHz)"
echo "  7) New Zealand (alternate)     (917.375 MHz)"
echo
read -rp "Region [1-7, default: 1]: " REGION_CHOICE
case "${REGION_CHOICE:-1}" in
    1) LORA_FREQ="910.525";    LORA_BW="250"; LORA_SF="11"; REGION_NAME="USA/Canada" ;;
    2) LORA_FREQ="907.875";    LORA_BW="250"; LORA_SF="11"; REGION_NAME="USA/Canada (alt 1)" ;;
    3) LORA_FREQ="927.875";    LORA_BW="250"; LORA_SF="11"; REGION_NAME="USA/Canada (alt 2)" ;;
    4) LORA_FREQ="869.525";    LORA_BW="250"; LORA_SF="11"; REGION_NAME="Europe/UK" ;;
    5) LORA_FREQ="868.731018"; LORA_BW="250"; LORA_SF="11"; REGION_NAME="Europe (alt)" ;;
    6) LORA_FREQ="915.8";      LORA_BW="250"; LORA_SF="11"; REGION_NAME="Australia/NZ" ;;
    7) LORA_FREQ="917.375";    LORA_BW="250"; LORA_SF="11"; REGION_NAME="New Zealand (alt)" ;;
    *)
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Build summary + confirmation
# ---------------------------------------------------------------------------
echo
echo -e "${BLUE}Build configuration:${NC}"
echo "  Environment : ${ENV_NAME}"
echo "  Region      : ${REGION_NAME} (${LORA_FREQ} MHz, BW=${LORA_BW} kHz, SF=${LORA_SF})"
echo "  INA3221     : enabled"
if [ -n "$MESHCORE_COMMIT" ]; then
    echo "  Commit      : $MESHCORE_COMMIT"
else
    echo "  Commit      : latest main"
fi
echo
read -rp "Continue with build? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ---------------------------------------------------------------------------
# Docker build context
# ---------------------------------------------------------------------------
mkdir -p "$DOCKER_CTX"

# The image contains ONLY the toolchain. All shell/python scripts and patches
# are bind-mounted at runtime from the host, so editing any of them takes
# effect on the next invocation without a Docker rebuild. Source code,
# patches, and firmware are regenerated from scratch every run.
cat > "$DOCKER_CTX/Dockerfile" <<'DOCKERFILE_EOF'
FROM python:3.12-slim
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        git curl build-essential udev && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --quiet platformio adafruit-nrfutil pyserial
DOCKERFILE_EOF

# ---------------------------------------------------------------------------
# Build Docker image (skip if already cached)
# ---------------------------------------------------------------------------
echo
echo -e "${YELLOW}Building Docker image (fresh every run)...${NC}"
docker build --no-cache -t "$IMAGE_TAG" "$DOCKER_CTX"

# ---------------------------------------------------------------------------
# Run firmware build inside container
# ---------------------------------------------------------------------------
echo
echo -e "${YELLOW}Compiling firmware...${NC}"
docker run --rm \
    -e ENV_NAME="$ENV_NAME" \
    -e LORA_FREQ="$LORA_FREQ" \
    -e LORA_BW="$LORA_BW" \
    -e LORA_SF="$LORA_SF" \
    -e MESHCORE_COMMIT="$MESHCORE_COMMIT" \
    -v "${ORIGINAL_PWD}:/output" \
    -v "${PATCHES_DIR}:/patches:ro" \
    -v "${HOST_SCRIPTS_DIR}:/scripts:ro" \
    --entrypoint /scripts/container_build.sh \
    "$IMAGE_TAG"

echo
ARTIFACTS=()
for f in "${ORIGINAL_PWD}"/firmware.zip \
          "${ORIGINAL_PWD}"/firmware.hex \
          "${ORIGINAL_PWD}"/firmware.uf2; do
    [ -f "$f" ] && ARTIFACTS+=("$f")
done

if [ ${#ARTIFACTS[@]} -eq 0 ]; then
    echo -e "${RED}Error: no firmware artifacts were produced.${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}"
echo "  Artifacts:"
for f in "${ARTIFACTS[@]}"; do
    size=$(du -sh "$f" | cut -f1)
    echo "    ${size}  ${f}"
done

# ---------------------------------------------------------------------------
# Flash
# ---------------------------------------------------------------------------
echo
read -rp "Flash firmware to device now? (y/N): " FLASH_CONFIRM
if [[ ! "$FLASH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo -e "${GREEN}Firmware saved to: ${ORIGINAL_PWD}/${NC}"
    echo -e "${GREEN}Done.${NC}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Shared helper: pick one item from a list, auto-select if only one exists.
#   select_item <label> <item1> [item2 ...]
#   Sets global SELECTED_ITEM on success; exits on error.
# ---------------------------------------------------------------------------
select_item() {
    local label="$1"
    shift
    local items=("$@")

    if [ ${#items[@]} -eq 0 ]; then
        echo -e "${RED}No ${label}s detected. Is the device plugged in?${NC}"
        exit 1
    elif [ ${#items[@]} -eq 1 ]; then
        SELECTED_ITEM="${items[0]}"
        echo -e "  Auto-selected ${label}: ${GREEN}${SELECTED_ITEM}${NC}"
    else
        echo "  Multiple ${label}s detected:"
        for i in "${!items[@]}"; do
            echo "    $((i+1))) ${items[$i]}"
        done
        read -rp "  Select ${label} [1-${#items[@]}]: " PICK
        local idx=$((PICK - 1))
        if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#items[@]}" ]; then
            echo -e "${RED}Invalid selection.${NC}"
            exit 1
        fi
        SELECTED_ITEM="${items[$idx]}"
        echo -e "  Selected ${label}: ${GREEN}${SELECTED_ITEM}${NC}"
    fi
}

# ---- Detect serial port on the host ----------------------------------------
echo -e "${YELLOW}Detecting serial ports...${NC}"
PORTS=()
for p in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$p" ] && PORTS+=("$p")
done

if [ ${#PORTS[@]} -eq 0 ]; then
    echo -e "${RED}No serial ports detected. Is the device plugged in?${NC}"
    echo
    echo "  If you want to flash manually via UF2 instead:"
    echo "    1. Double-tap RESET to enter bootloader mode (LED will pulse)"
    echo "    2. The device mounts as a USB drive"
    echo "    3. Copy the firmware:  cp '${ORIGINAL_PWD}/firmware.uf2' <mount-point>/"
    exit 1
fi

select_item "serial port" "${PORTS[@]}"
FLASH_PORT="$SELECTED_ITEM"

# ---- Flash inside Docker ---------------------------------------------------
# The container runs with --privileged and shares the host /dev tree so it
# can perform the 1200 bps DFU touch AND see the device re-enumerate — no
# host-side tools (adafruit-nrfutil, nrfjprog, etc.) required.
echo
echo -e "${YELLOW}Flashing inside Docker container...${NC}"
echo -e "  Port      : ${GREEN}${FLASH_PORT}${NC}"
echo -e "  Package   : firmware.zip"
echo -e "  USB access: --privileged + /dev bind-mount"
echo

docker run --rm \
    --privileged \
    -v /dev:/dev \
    -v "${ORIGINAL_PWD}:/firmware:ro" \
    -v "${HOST_SCRIPTS_DIR}:/scripts:ro" \
    -e FLASH_PORT="$FLASH_PORT" \
    --entrypoint /scripts/container_flash.sh \
    "$IMAGE_TAG"

echo
echo -e "${GREEN}Done.${NC}"
