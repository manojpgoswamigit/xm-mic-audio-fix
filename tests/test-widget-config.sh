#!/usr/bin/env bash
# =============================================================================
#  Plasma widget configuration contract
# =============================================================================
#  Plasma's applet configuration dialog copies every main.xml key into a
#  `cfg_<key>` property on the page and saves it back on Apply. A missing or
#  misnamed alias silently discards the user's settings, so keep the three
#  files in lockstep:
#
#      contents/config/main.xml       keys
#      contents/ui/ConfigGeneral.qml  cfg_<key> aliases
#      contents/ui/main.qml           readCfg("<key>") lookups
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$repo_root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]) / "plasmoid"
xml_path = root / "contents/config/main.xml"
config_path = root / "contents/config/config.qml"
page_path = root / "contents/ui/ConfigGeneral.qml"
main_path = root / "contents/ui/main.qml"

for path in (xml_path, config_path, page_path, main_path):
    if not path.is_file():
        raise SystemExit(f"FAIL: missing {path.relative_to(root.parent)}")

xml = xml_path.read_text(encoding="utf-8")
config = config_path.read_text(encoding="utf-8")
page = page_path.read_text(encoding="utf-8")
main = main_path.read_text(encoding="utf-8")

keys = set(re.findall(r'<entry\s+name="([^"]+)"', xml))
aliases = set(re.findall(r'property\s+alias\s+cfg_([A-Za-z0-9_]+)\s*:', page))
read_keys = set(re.findall(r'readCfg\("([^"]+)"', main))

errors = []
if not keys:
    errors.append("main.xml has no <entry name=...> keys")
if read_keys - keys:
    errors.append(f"main.qml reads unknown keys: {sorted(read_keys - keys)}")
if aliases - keys:
    errors.append(f"ConfigGeneral.qml defines unknown aliases: {sorted(aliases - keys)}")
missing_aliases = keys - aliases
if missing_aliases:
    errors.append(f"ConfigGeneral.qml is missing cfg_ aliases: {sorted(missing_aliases)}")

if "ConfigModel" not in config or 'source: "ConfigGeneral.qml"' not in config:
    errors.append("config.qml must be a ConfigModel pointing at ConfigGeneral.qml")
if "ConfigPage" in config:
    errors.append("config.qml must not use the old ConfigPage root")

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: {len(keys)} config keys, {len(aliases)} cfg_ aliases, "
      f"{len(read_keys)} readCfg lookups")
PY
