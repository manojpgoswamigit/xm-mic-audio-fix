#!/usr/bin/env bash
# ==============================================================================
# XM Bluetooth Headset Meeting Fix - Uninstaller
# ==============================================================================
# Removes the user-level files installed by install.sh. Does not touch any
# system packages. Reverses everything cleanly.
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

BIN_TARGET="${HOME}/.local/bin/xm"
CONF_TARGET="${HOME}/.config/wireplumber/wireplumber.conf.d/51-bt-calls.conf"

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}      XM Bluetooth Headset Meeting Fix (xm) - Uninstaller              ${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo -e "${RED}[X] Do not run as root. This removes files from your \$HOME.${NC}"
    exit 1
fi

# If the Plasma widget is installed, route through the graded uninstaller so
# the applet leaves the panel and its package is removed cleanly too.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "${HOME}/.local/share/plasma/plasmoids/com.manojpgoswami.xmwidget" ] \
   || [ -f "${HOME}/.local/state/xm-widget/manifest" ]; then
    echo -e " ${YELLOW}Note:${NC} the KDE panel widget is installed."
    echo -e "       Removing it too (equivalent to ./rollback.sh)."
    echo
    exec "${SCRIPT_DIR}/uninstall-widget.sh" --all --restart
fi

rm -f "$BIN_TARGET"
echo -e " ${GREEN}✓${NC} Removed $BIN_TARGET"

rm -f "$CONF_TARGET"
echo -e " ${GREEN}✓${NC} Removed $CONF_TARGET"

# Restart WirePlumber so the setting reverts to defaults
echo
echo -e "${CYAN}${BOLD}Restarting WirePlumber to apply defaults...${NC}"
if systemctl --user restart wireplumber 2>/dev/null; then
    echo -e " ${GREEN}✓${NC} WirePlumber restarted (auto-switch restored to default 'on')"
else
    echo -e " ${YELLOW}!${NC} Run manually: systemctl --user restart wireplumber"
fi

echo
echo -e "${GREEN}${BOLD}✓ Uninstallation complete!${NC}"
echo
echo -e "${CYAN}Tip:${NC} if you also installed the KDE panel widget, run"
echo -e "     ${BOLD}./rollback.sh${NC}   (removes the widget too, with a full restore)"
