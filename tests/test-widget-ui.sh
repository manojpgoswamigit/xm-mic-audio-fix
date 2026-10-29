#!/usr/bin/env bash
# Real QML interaction and geometry probes; requires Qt 6 Quick Test + Plasma.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if command -v qmltestrunner6 >/dev/null; then
    runner=$(command -v qmltestrunner6)
elif command -v qtpaths6 >/dev/null; then
    runner="$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner"
elif [ -x /usr/lib/qt6/bin/qmltestrunner ]; then
    runner=/usr/lib/qt6/bin/qmltestrunner
elif [ -x /usr/lib64/qt6/bin/qmltestrunner ]; then
    runner=/usr/lib64/qt6/bin/qmltestrunner
else
    echo 'Qt 6 Quick Test tools (qmltestrunner) are required.' >&2
    exit 1
fi
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=KDE
timeout 30 "$runner" -input "$repo_root/tests/qml"
