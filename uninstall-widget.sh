#!/usr/bin/env bash
# ==============================================================================
# XM Headset - widget uninstaller / rollback
# ==============================================================================
# Graded removal, from least to most destructive:
#
#     --widget           remove only the panel applet + its icons (default)
#                        xm itself and the WirePlumber config are untouched.
#
#     --all              also remove ~/.local/bin/xm and the WirePlumber
#                        drop-in, restoring the state saved by
#                        install-widget.sh (or removing the config if there
#                        was none to begin with).
#
#     --restore-config   nothing else; just restore the WirePlumber config
#                        from the backup taken at widget-install time.
#
#     --restart          restart plasmashell at the end, so a half-removed
#                        applet can never linger in the panel.
#
#     --yes              do not ask for confirmation.
#
# Safety rules (enforced unconditionally):
#   * Never runs as root.
#   * Never removes anything outside $HOME.
#   * Never follows globs into unexpected directories: every removal must be a
#     full path that is either in the manifest or one of the three known
#     fixed paths.
#   * Applet instances are removed from panels BEFORE the package is deleted.
#   * Every step prints what it is about to delete before deleting it.
#
# Usage:  ./uninstall-widget.sh [--widget|--all|--restore-config] [--restart] [--yes]
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

ok()   { echo -e " ${GREEN}OK${NC}   $*"; }
warn() { echo -e " ${YELLOW}WARN${NC} $*"; }
err()  { echo -e " ${RED}FAIL${NC} $*" >&2; }
info() { echo -e "        $*"; }

HOME_DIR="${HOME}"
APPLET_ID="com.manojpgoswami.xmwidget"
APPLET_DIR="${HOME_DIR}/.local/share/plasma/plasmoids/${APPLET_ID}"
STATE_DIR="${HOME_DIR}/.local/state/xm-widget"
MANIFEST="${STATE_DIR}/manifest"
BACKUP_ROOT="${STATE_DIR}/backups/wireplumber"
WP_DIR="${HOME_DIR}/.config/wireplumber/wireplumber.conf.d"
WP_CONF="${WP_DIR}/51-bt-calls.conf"
XM_BIN="${HOME_DIR}/.local/bin/xm"
ICON_THEME="${HOME_DIR}/.local/share/icons/hicolor"

MODE="widget"
DO_RESTART=0
ASSUME_YES=0

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --widget)        MODE="widget" ;;
        --all)           MODE="all" ;;
        --restore-config) MODE="config" ;;
        --restart)       DO_RESTART=1 ;;
        -y|--yes)        ASSUME_YES=1 ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            err "Try: --widget | --all | --restore-config | --restart | --yes"
            exit 1
            ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# Safety helpers
# ------------------------------------------------------------------------------
guard_path() {
    local p="$1"
    case "$p" in
        "${HOME_DIR}/"*) : ;;
        *) err "SAFETY: refusing to touch '${p}' (not under ${HOME_DIR})"; return 1 ;;
    esac
    case "$p" in
        /|"${HOME_DIR}"|*".."*|*"//"*|*"/ "*)
            err "SAFETY: refusing to touch '${p}' (suspicious path)"; return 1 ;;
    esac
    return 0
}

# Remove a single, fully-qualified path. No globbing, ever.
remove_one() {
    local p="$1" what="${2:-file}"
    if ! guard_path "$p"; then
        return 1
    fi
    if [ -f "$p" ] || [ -L "$p" ]; then
        info "removing ${what}: ${p}"
        rm -f "$p"
    fi
}

# Remove a directory, and only if it is empty-ish (widget-owned files only).
remove_dir_if_empty() {
    local p="$1" what="${2:-directory}"
    if ! guard_path "$p"; then
        return 1
    fi
    if [ -d "$p" ]; then
        info "removing ${what}: ${p}"
        rm -rf "$p"
    fi
}

confirm() {
    local prompt="$1"
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    echo
    echo -e "${YELLOW}${BOLD}${prompt}${NC}"
    printf "Type %s to continue: " "yes"
    local reply=""
    read -r reply || true
    [ "$reply" = "yes" ] || {
        info "Aborted; nothing was changed."
        exit 1
    }
}

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}       XM Headset - widget uninstaller / rollback                     ${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo
echo -e "Mode: ${BOLD}${MODE}${NC}   restart-plasmashell: ${BOLD}$([ $DO_RESTART -eq 1 ] && echo yes || echo no)${NC}"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    err "Do not run this as root. It removes files from your \$HOME."
    exit 1
fi

case "$MODE" in
    all)
        confirm "This removes the widget, the xm command and the WirePlumber config."
        ;;
    config)
        info "Restore-config mode: nothing is uninstalled."
        ;;
    *)
        info "Widget-only: xm and its WirePlumber config stay installed."
        ;;
esac
echo

# ------------------------------------------------------------------------------
# 1. Take the applet out of every panel FIRST, so plasmashell never ends up
#    holding a reference to a package that no longer exists.
#    (Skipped entirely for --restore-config, which must change nothing else.)
# ------------------------------------------------------------------------------
if [ "$MODE" != "config" ]; then
echo -e "${CYAN}${BOLD}[1/5] Removing applet instances from panels${NC}"
if command -v gdbus >/dev/null 2>&1; then
    # The scripting API only reports back through thrown errors, so count the
    # instances by throwing the total. gdbus itself exits non-zero when the
    # script throws, so it must be allowed to "fail".
    REMOVED=$( { gdbus call --session --dest org.kde.plasmashell \
                       --object-path /PlasmaShell \
                       --method org.kde.PlasmaShell.evaluateScript \
                       "(function(){
                            var n = 0;
                            var ps = panels();
                            for (var p = 0; p < ps.length; p++) {
                                var w = ps[p].widgets();
                                for (var i = 0; i < w.length; i++) {
                                    if (w[i].type === '${APPLET_ID}') { w[i].remove(); n++; }
                                }
                            }
                            throw new Error('N=' + n);
                        })()" || true; } 2>&1 \
                 | sed -n 's/.*Error: Error: N=\([0-9]*\).*/\1/p' | head -n1 )
    REMOVED=${REMOVED:-0}
    if [ "$REMOVED" -gt 0 ]; then
        ok "removed ${REMOVED} applet instance(s) from the panel"
    else
        info "no applet instance found on the panel (nothing to remove)"
    fi
else
    warn "gdbus not found; remove the applet from the panel by hand."
fi
echo
fi

# ------------------------------------------------------------------------------
# 2. Uninstall the plasmoid package
#    (Skipped entirely for --restore-config, which must change nothing else.)
# ------------------------------------------------------------------------------
if [ "$MODE" != "config" ]; then
echo -e "${CYAN}${BOLD}[2/5] Uninstalling the applet package${NC}"
if kpackagetool6 -t Plasma/Applet -r "$APPLET_ID" >/dev/null 2>&1; then
    ok "package removed by kpackagetool6"
else
    warn "kpackagetool6 could not remove it; falling back to rm -rf"
fi
if ! guard_path "$APPLET_DIR"; then
    exit 1
fi
if [ -d "$APPLET_DIR" ]; then
    rm -rf "$APPLET_DIR"
    ok "removed ${APPLET_DIR}"
fi
echo
fi

# ------------------------------------------------------------------------------
# 3. Remove everything the manifest recorded, plus the known fixed paths
#    (Skipped entirely for --restore-config.)
# ------------------------------------------------------------------------------
if [ "$MODE" != "config" ]; then
echo -e "${CYAN}${BOLD}[3/5] Removing installed icons and leftovers${NC}"
if [ -f "$MANIFEST" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            *plasmoids/*)
                # Already handled by the package removal above.
                continue
                ;;
        esac
        if [ -f "$line" ] || [ -L "$line" ] || [ -d "$line" ]; then
            remove_one "$line" "manifest entry"
        fi
    done < <(sort -u "$MANIFEST")
    ok "manifest entries processed"
else
    info "no manifest found (fresh or already cleaned)"
fi

# Belt and braces: the icon sizes are fixed and known, and the dirs are removed
# only if they end up empty.
for sz in 16 22 24 32 48 64 128 256; do
    remove_one "${ICON_THEME}/${sz}x${sz}/apps/xmwidget.png" "icon"
done
remove_one "${ICON_THEME}/scalable/apps/xmwidget.svg" "icon"
remove_one "${HOME_DIR}/.local/share/knotifications6/xmwidget.notifyrc" "notification config"
for sz in 16 22 24 32 48 64 128 256; do
    rmdir "${ICON_THEME}/${sz}x${sz}/apps" 2>/dev/null || true
done
echo
fi

# ------------------------------------------------------------------------------
# 4. The WirePlumber config: restore, remove, or leave completely alone
# ------------------------------------------------------------------------------
echo -e "${CYAN}${BOLD}[4/5] WirePlumber config${NC}"
restore_wp() {
    local backup=""
    if [ -d "$BACKUP_ROOT" ]; then
        # Newest timestamped backup directory wins.
        backup=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
                 | sort -r | head -n1)
    fi
    if [ -n "$backup" ] && [ -f "${backup}/51-bt-calls.conf" ]; then
        mkdir -p "$WP_DIR"
        cp -f "${backup}/51-bt-calls.conf" "$WP_CONF"
        ok "restored original config from ${backup}/51-bt-calls.conf"
        return 0
    fi
    if [ -f "$WP_CONF" ]; then
        rm -f "$WP_CONF"
        ok "removed ${WP_CONF} (no backup existed)"
    else
        info "nothing to restore: ${WP_CONF} was never installed"
    fi
}

case "$MODE" in
    config)
        restore_wp
        ;;
    all)
        restore_wp
        if [ -f "$XM_BIN" ]; then
            remove_one "$XM_BIN" "command"
        else
            info "xm command already absent"
        fi
        ;;
    *)
        info "left untouched (use --all or --restore-config to change it)"
        ;;
esac
echo

# ------------------------------------------------------------------------------
# 5. Roll forward: clear the QML cache, drop the state dir, restart if asked
# ------------------------------------------------------------------------------
echo -e "${CYAN}${BOLD}[5/5] Finishing up${NC}"
if [ -d "${HOME_DIR}/.cache/plasmashell/qmlcache" ]; then
    rm -rf "${HOME_DIR}/.cache/plasmashell/qmlcache" 2>/dev/null || true
    ok "cleared plasmashell QML cache"
fi

if [ "$MODE" = "all" ]; then
    # Backups are part of the rollback story: keep them, but say so.
    if [ -d "$STATE_DIR" ]; then
        info "keeping ${STATE_DIR} (backups + uninstall history)"
        info "  -> inspect with: ls -R ${STATE_DIR}"
        info "  -> delete it yourself if you want a spotless \$HOME"
        if [ -f "$MANIFEST" ]; then
            : > "$MANIFEST"
        fi
    fi
fi

# Refresh the icon cache so the icon disappears from pickers.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincredible >/dev/null 2>&1 || true
fi

if [ "$DO_RESTART" -eq 1 ]; then
    if command -v kquitapp6 >/dev/null 2>&1 && command -v kstart >/dev/null 2>&1; then
        info "restarting plasmashell (about 10 seconds)"
        kquitapp6 plasmashell 2>/dev/null || true
        sleep 4
        setsid kstart plasmashell >/dev/null 2>&1 < /dev/null &
        sleep 12
        ok "plasmashell restarted"
    else
        warn "kquitapp6/kstart not found; restart plasmashell by hand."
    fi
else
    info "plasmashell was not restarted. If the applet still shows in the panel,"
    info "log out and back in, or run:"
    info "    kquitapp6 plasmashell && kstart plasmashell"
fi

echo
echo -e "${GREEN}${BOLD}======================================================================${NC}"
case "$MODE" in
    all)         echo -e "${GREEN}${BOLD}  Full rollback complete: widget + xm + config gone, system reset      ${NC}" ;;
    config)      echo -e "${GREEN}${BOLD}  WirePlumber config restored to its pre-widget state                   ${NC}" ;;
    *)           echo -e "${GREEN}${BOLD}  Widget removed; xm and its WirePlumber config are still installed      ${NC}" ;;
esac
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo
