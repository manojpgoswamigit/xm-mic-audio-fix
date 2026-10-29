#!/usr/bin/env bash
# =============================================================================
#  Regenerate the README screenshots and widget demo GIF
# =============================================================================
#  Renders the real HeadsetPopup.qml through preview/preview.qml, offscreen.
#  QT_QPA_PLATFORMTHEME=KDE is required: without a platform theme Kirigami.Icon
#  silently ignores its `color` property in offscreen Qt, so every symbolic
#  icon comes out black even though the live plasmashell render is correct.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

out_dir=${1:-assets}
tmp_dir=${TMPDIR:-/tmp}/xm-widget-preview
mkdir -p "$out_dir" "$tmp_dir"

command -v qml6 >/dev/null || { echo "qml6 is required" >&2; exit 1; }
command -v magick >/dev/null || { echo "ImageMagick (magick) is required" >&2; exit 1; }

render() {
    local state=$1 theme=$2 name=$3
    local theme_arg=()
    [[ $theme == dark ]] && theme_arg=(dark)

    echo "rendering $theme/$state -> $out_dir/$name.png"
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
        qml6 preview/preview.qml -- "${theme_arg[@]}" \
        "--state=$state" --auto-height --scale=2 --out="$out_dir/$name.png" >/dev/null
}

render a2dp  light screenshot-light
render a2dp  dark  screenshot-dark
render live  dark  screenshot-waveform
render about dark  screenshot-modal

# Legacy asset names kept in sync for older links.
cp "$out_dir/screenshot-dark.png" "$out_dir/widget-screenshot.png"

# Five-frame showcase: Call, listening, result, About, Music.
for frame in hfp testing live about a2dp; do
    echo "rendering demo frame $frame"
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
        qml6 preview/preview.qml -- dark "--state=$frame" --height=505 --scale=2 \
        --out="$tmp_dir/gif-$frame.png" >/dev/null
done

magick \
    -delay 160 "$tmp_dir/gif-hfp.png" \
    -delay 120 "$tmp_dir/gif-testing.png" \
    -delay 220 "$tmp_dir/gif-live.png" \
    -delay 180 "$tmp_dir/gif-about.png" \
    -delay 160 "$tmp_dir/gif-a2dp.png" \
    -loop 0 -layers Optimize "$out_dir/widget-demo.gif"

cp "$out_dir/widget-demo.gif" "$out_dir/demo.gif"
echo "done: $out_dir"
