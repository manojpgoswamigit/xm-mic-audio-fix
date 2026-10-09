#!/usr/bin/env bash
# ==============================================================================
# XM Headset - KDE Plasma widget installer
# ==============================================================================
# Installs ONE thing: the "XM Headset" panel applet, which is a click-runner
# for the `xm` command. It changes nothing about your audio configuration.
#
#   * Installed user-level, no root, no new packages.
#   * Every file it creates is recorded in a manifest, so the uninstaller can
#     remove exactly what was added and nothing else.
#   * The pre-install state of the WirePlumber config is backed up, so a full
#     rollback can put the machine back exactly the way it was.
#   * It never restarts plasmashell: the panel keeps working, and the applet
#     shows up in "Add Widgets" immediately.
#
# Usage:   ./install-widget.sh
# Requires: xm (see install.sh), plasma 6, kpackagetool6,
#           rsvg-convert OR magick OR convert (any one of them)
# ==============================================================================

set -euo pipefail

# ANSI styling
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

ok()   { echo -e " ${GREEN}OK${NC}   $*"; }
warn() { echo -e " ${YELLOW}WARN${NC} $*"; }
err()  { echo -e " ${RED}FAIL${NC} $*" >&2; }
info() { echo -e "        $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPLET_ID="com.manojpgoswami.xmwidget"
PLASMOID_SRC="${SCRIPT_DIR}/plasmoid"
ICON_SRC="${SCRIPT_DIR}/assets/xmwidget.svg"

APPLET_DIR="${HOME}/.local/share/plasma/plasmoids/${APPLET_ID}"
STATE_DIR="${HOME}/.local/state/xm-widget"
MANIFEST="${STATE_DIR}/manifest"
BACKUP_ROOT="${STATE_DIR}/backups/wireplumber"
WP_CONF="${HOME}/.config/wireplumber/wireplumber.conf.d/51-bt-calls.conf"
XM_BIN="${HOME}/.local/bin/xm"
NOTIFY_SRC="${SCRIPT_DIR}/assets/xmwidget.notifyrc"
NOTIFY_DIR="${HOME}/.local/share/knotifications6"

# Rendered at install time, not committed: keeps the repo small and lets the
# host pick the exact pixel sizes it wants.
ICON_SIZES=(16 22 24 32 48 64 128 256)
ICON_THEME="${HOME}/.local/share/icons/hicolor"

STAMP="$(date +%Y%m%d%H%M%S)"

# ------------------------------------------------------------------------------
# Shared helpers (kept in sync with uninstall-widget.sh)
# ------------------------------------------------------------------------------

# Absolute path only, and only under $HOME. Refuse anything else, always.
guard_path() {
    local p="$1"
    case "$p" in
        "${HOME}/"*) : ;;
        *) err "refusing to touch '${p}': not under ${HOME}"; return 1 ;;
    esac
    case "$p" in
        *".."*|*"//"*|*"/ "*) err "refusing to touch '${p}': suspicious path"; return 1 ;;
    esac
    return 0
}

add_manifest() {
    printf '%s\n' "$1" >> "$MANIFEST"
}

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}       XM Headset - Plasma panel widget installer                    ${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo

# --- Gate 1: never root ------------------------------------------------------
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    err "Do not run this as root/sudo. It installs files under your \$HOME only."
    exit 1
fi

# --- Gate 2: preflight -------------------------------------------------------
echo -e "${CYAN}${BOLD}[Preflight]${NC}"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    err "kpackagetool6 not found. This widget needs Plasma 6."
    exit 1
fi
ok "kpackagetool6 present"

PLASMA_MAJOR="$(plasmashell --version 2>/dev/null | tr -dc '0-9' | head -c 1 || true)"
if [ "${PLASMA_MAJOR:-0}" = "6" ]; then
    ok "Plasma 6 detected"
else
    warn "Could not confirm Plasma 6 (widgets need it); continuing anyway."
fi

# Icon rendering: any one of these is enough.
RENDERER=""
for c in rsvg-convert magick convert; do
    if command -v "$c" >/dev/null 2>&1; then RENDERER="$c"; break; fi
done
if [ -z "$RENDERER" ]; then
    warn "No SVG->PNG renderer found (tried rsvg-convert, magick, convert)."
    warn "Installing the SVG only: the widget still works, just less crisp."
    render_icons() { :; }
else
    ok "icon renderer: ${RENDERER}"
    render_icons() {
        local svg="$1" out="$2" sz="$3"
        case "$RENDERER" in
            rsvg-convert) rsvg-convert -w "$sz" -h "$sz" "$svg" -o "$out" ;;
            magick)       magick -background none -density 384 \
                              "$svg" -resize "${sz}x${sz}" "$out" ;;
            convert)      convert -background none -density 384 \
                              "$svg" -resize "${sz}x${sz}" "$out" ;;
        esac
    }
fi

if [ -x "$XM_BIN" ]; then
    ok "xm found at ${XM_BIN}"
else
    warn "xm not found at ${XM_BIN}."
    warn "The widget will install and show a 'no headset / no xm' state until you run:"
    warn "    ${SCRIPT_DIR}/install.sh"
fi
echo

# --- Gate 3: state dir + manifest -------------------------------------------
echo -e "${CYAN}${BOLD}[1/5] Preparing state directory${NC}"
if [ -f "$MANIFEST" ]; then
    warn "A previous manifest exists; it will be appended to (uninstall cleans all)."
else
    mkdir -p "$STATE_DIR"
fi
touch "$MANIFEST"
ok "manifest: ${MANIFEST}"
echo

# --- Gate 4: back up the current WirePlumber config -------------------------
echo -e "${CYAN}${BOLD}[2/5] Backing up the current WirePlumber config${NC}"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
mkdir -p "$BACKUP_DIR"
if [ -f "$WP_CONF" ]; then
    cp -f "$WP_CONF" "${BACKUP_DIR}/51-bt-calls.conf"
    info "existing config saved to ${BACKUP_DIR}/51-bt-calls.conf"
    PRESENT=yes
else
    info "no xm config installed right now"
    PRESENT=no
fi
{
    echo "timestamp=${STAMP}"
    echo "plasma=${PLASMA_MAJOR:-unknown}"
    echo "wireplumber_conf=${WP_CONF}"
    echo "config_existed=${PRESENT}"
    echo "widget_id=${APPLET_ID}"
} > "${BACKUP_DIR}/info.env"
ok "backup recorded (config_existed=${PRESENT})"
echo

# --- Step 5a: install the plasmoid ------------------------------------------
echo -e "${CYAN}${BOLD}[3/5] Installing the panel applet${NC}"
if [ -d "$APPLET_DIR" ]; then
    info "an older copy exists; removing it first (it is in the manifest history)"
fi
# kpackagetool6 refuses to install over an existing dir, so remove first.
kpackagetool6 -t Plasma/Applet -r "$APPLET_ID" >/dev/null 2>&1 || true
rm -rf "$APPLET_DIR"
kpackagetool6 -t Plasma/Applet -i "$PLASMOID_SRC"
add_manifest "$APPLET_DIR"
ok "applet installed at ${APPLET_DIR}"
echo

# --- Step 5b: install the icons ---------------------------------------------
echo -e "${CYAN}${BOLD}[4/5] Installing the applet icon${NC}"
mkdir -p "${ICON_THEME}/scalable/apps"
install -m644 "$ICON_SRC" "${ICON_THEME}/scalable/apps/xmwidget.svg"
add_manifest "${ICON_THEME}/scalable/apps/xmwidget.svg"
ok "svg icon installed"

if [ -n "$RENDERER" ]; then
    for sz in "${ICON_SIZES[@]}"; do
        dir="${ICON_THEME}/${sz}x${sz}/apps"
        mkdir -p "$dir"
        render_icons "$ICON_SRC" "${dir}/xmwidget.png" "$sz"
        add_manifest "${dir}/xmwidget.png"
    done
    ok "rendered PNGs: ${ICON_SIZES[*]}"
fi

if [ -f "$NOTIFY_SRC" ]; then
    mkdir -p "$NOTIFY_DIR"
    install -m644 "$NOTIFY_SRC" "${NOTIFY_DIR}/xmwidget.notifyrc"
    add_manifest "${NOTIFY_DIR}/xmwidget.notifyrc"
    ok "notification config installed"
fi

# Refresh the icon cache so the widget can find the icon right away.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincredible >/dev/null 2>&1 || true
    ok "icon cache refreshed (kbuildsycoca6)"
else
    warn "kbuildsycoca6 not found; you may need to log out and back in."
fi
echo

# --- Step 5c: caches and summary --------------------------------------------
echo -e "${CYAN}${BOLD}[5/5] Refreshing caches${NC}"
# Only the cache: plasmashell is never restarted by this script.
if [ -d "${HOME}/.cache/plasmashell/qmlcache" ]; then
    rm -rf "${HOME}/.cache/plasmashell/qmlcache" 2>/dev/null || true
    ok "stale QML cache cleared"
fi
info "plasmashell was NOT restarted on purpose: keep working, then add the widget."
echo

echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}                  Widget installed                                    ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo
info "Add it to the panel:"
info "  right-click the panel -> Add Widgets -> search 'XM' -> drag 'XM Headset'"
echo
info "Or restart plasmashell to reset its QML cache:"
info "  kquitapp6 plasmashell && kstart plasmashell"
echo
info "Undo everything with:"
info "  ${SCRIPT_DIR}/rollback.sh        (widget + xm + WirePlumber config)"
info "  ${SCRIPT_DIR}/uninstall-widget.sh --widget   (widget only)"
echo
info "Full state is tracked in:"
info "  ${MANIFEST}"
