#!/usr/bin/env bash
# ==============================================================================
# XM Bluetooth Headset Meeting Fix - Installer
# ==============================================================================
# Installs:
#   1. CLI helper:  ~/.local/bin/xm
#   2. WirePlumber drop-in: ~/.config/wireplumber/wireplumber.conf.d/51-bt-calls.conf
#
# Both are user-level and fully reversible via uninstall.sh
# ==============================================================================

set -euo pipefail

# ANSI color styling
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}      XM Bluetooth Headset Meeting Fix (xm) - Installer & Setup       ${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo

# --- Preflight: prevent running as root --------------------------------------
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo -e "${RED}[X] Error: Please do not run this installer as root/sudo.${NC}"
    echo -e "    It installs user-level files in ~/.local/bin and ~/.config."
    exit 1
fi

# --- Preflight: check the audio stack ----------------------------------------
echo -e "${CYAN}${BOLD}[Preflight] Checking audio stack...${NC}"
missing=""
for cmd in pactl wpctl bluetoothctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e " ${GREEN}OK${NC}   $cmd"
    else
        echo -e " ${RED}MISS${NC} $cmd"
        missing="$missing $cmd"
    fi
done
if [ -n "$missing" ]; then
    echo
    echo -e "${RED}[X] Missing required commands:${NC}$missing"
    echo -e "    Install them with (CachyOS/Arch):"
    echo -e "      ${BOLD}sudo pacman -S --needed pipewire pipewire-pulse wireplumber bluez bluez-utils${NC}"
    exit 1
fi
echo

# --- Sanity check: are we on PipeWire (not raw PulseAudio)? -------------------
if pactl info 2>/dev/null | grep -q "PulseAudio (on PipeWire)"; then
    echo -e "${GREEN}OK${NC}   Audio server is PulseAudio-on-PipeWire (correct)."
else
    echo -e "${YELLOW}[!] Could not confirm PipeWire as the audio server.${NC}"
    echo -e "    This fix targets PipeWire + WirePlumber. Continuing anyway..."
fi
echo

BIN_DIR="${HOME}/.local/bin"
WP_CONF_DIR="${HOME}/.config/wireplumber/wireplumber.conf.d"

mkdir -p "$BIN_DIR" "$WP_CONF_DIR"

# --- Step 1: install the xm command ------------------------------------------
echo -e "${CYAN}${BOLD}[1/2] Installing 'xm' command to ${BIN_DIR}/xm ...${NC}"
install -m 755 "${SCRIPT_DIR}/xm.sh" "${BIN_DIR}/xm"
echo -e " ${GREEN}✓${NC} Executable installed at ${BOLD}${BIN_DIR}/xm${NC}"
echo

# --- Step 2: install the WirePlumber config (with backup) --------------------
CONF_TARGET="${WP_CONF_DIR}/51-bt-calls.conf"
echo -e "${CYAN}${BOLD}[2/2] Installing WirePlumber config to ${CONF_TARGET} ...${NC}"
if [ -f "$CONF_TARGET" ]; then
    cp -f "$CONF_TARGET" "${CONF_TARGET}.bak.$(date +%Y%m%d%H%M%S)"
    echo -e " ${YELLOW}!${NC} Existing config backed up (${CONF_TARGET}.bak.*)"
fi
install -m 644 "${SCRIPT_DIR}/51-bt-calls.conf" "$CONF_TARGET"
echo -e " ${GREEN}✓${NC} Config installed"
echo

# --- Restart WirePlumber so the config takes effect --------------------------
echo -e "${CYAN}${BOLD}Applying changes (restarting WirePlumber)...${NC}"
systemctl --user restart wireplumber 2>/dev/null && echo -e " ${GREEN}✓${NC} WirePlumber restarted" \
    || { echo -e " ${YELLOW}!${NC} Could not restart WirePlumber automatically."; \
         echo -e "    Run manually: ${BOLD}systemctl --user restart wireplumber${NC}"; }

# --- PATH reminder ------------------------------------------------------------
case ":${PATH}:" in
    *":${BIN_DIR}:"*) : ;;
    *)
        echo
        echo -e "${YELLOW}[!] ${BIN_DIR} is not on your PATH.${NC}"
        echo -e "    Add this to your shell config (e.g. ~/.config/fish/config.fish):"
        echo -e "      ${BOLD}fish_add_path ${BIN_DIR}${NC}"
        ;;
esac

echo
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}                 Installation complete!                                ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo
echo -e "How to use it:"
echo -e "  ${BOLD}xm call${NC}    -> before a meeting (mic + speaker both work)"
echo -e "  ${BOLD}xm music${NC}   -> after a meeting (back to hi-fi LDAC)"
echo -e "  ${BOLD}xm test${NC}    -> record 5s and check if your mic is live"
echo -e "  ${BOLD}xm fix${NC}     -> rescue a silent/connected mic"
echo -e "  ${BOLD}xm status${NC}  -> show current profile"
echo
echo -e "In Teams/Zoom set Speaker = your headset and Microphone = your headset."
echo
