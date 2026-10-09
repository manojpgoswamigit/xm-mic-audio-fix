#!/usr/bin/env bash
# ==============================================================================
# xm - full rollback
# ==============================================================================
# The "get me back to a clean reset" command.
#
#     ./rollback.sh
#
# is exactly:
#
#     ./uninstall-widget.sh --all --restart
#
# i.e. it removes the panel applet, the xm command and the WirePlumber
# drop-in, restores the WirePlumber configuration to whatever it was before
# the widget was installed, and restarts plasmashell so the panel is clean.
#
# The WirePlumber backups taken by install-widget.sh are deliberately KEPT in
#     ~/.local/state/xm-widget/backups/
# so you can still inspect what changed. Delete that directory yourself if
# you want a spotless \$HOME.
#
# Add "--yes" to skip the confirmation prompt.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/uninstall-widget.sh" --all --restart "$@"
