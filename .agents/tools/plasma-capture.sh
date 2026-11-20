#!/usr/bin/env bash
# Capture a temporary, uniquely named copy of any applet in this repo without touching the
# installed one: plasma-capture.sh PLASMOID_DIR OUTPUT.png [full|horizontal|vertical] [seconds]
# "full" opens the popup content in plasmawindowed; the others add a throwaway panel.
# PLASMA_CAPTURE_CONFIG="key=value key2=value2" overrides config defaults in main.xml.
# PLASMA_CAPTURE_THICKNESS sets the throwaway panel's thickness in pixels (default 46).
set -euo pipefail

source_tree=$(cd "${1:?usage: plasma-capture.sh PLASMOID_DIR OUTPUT.png [presentation] [seconds]}" && pwd)
output=${2:?usage: plasma-capture.sh PLASMOID_DIR OUTPUT.png [presentation] [seconds]}
presentation=${3:-full}
delay_ms=$(( ${4:-6} * 1000 ))
[[ "$presentation" == full || "$presentation" == horizontal || "$presentation" == vertical ]]

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasma-capture.XXXXXX")
package_dir="$scratch_dir/package"
capture_path="$scratch_dir/capture.png"
package_id=""
panel_id=""

cleanup() {
    [[ -n ${window_pid:-} ]] && { kill "$window_pid" 2>/dev/null || true; wait "$window_pid" 2>/dev/null || true; }
    if [[ -n "$panel_id" ]]; then
        qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            "var p = panelById($panel_id); if (p) p.remove();" >/dev/null 2>&1 || true
    fi
    [[ -n "$package_id" ]] && kpackagetool6 -t Plasma/Applet -r "$package_id" >/dev/null 2>&1 || true
    rm -rf "$scratch_dir"
}
trap cleanup EXIT

cp -a "$source_tree" "$package_dir"
original_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])' "$package_dir/metadata.json")
package_id="$original_id.capture$(basename "$scratch_dir" | tr -cd '[:alnum:]')"
sed -i "s/\"$original_id\"/\"$package_id\"/" "$package_dir/metadata.json"

for pair in ${PLASMA_CAPTURE_CONFIG:-}; do
    key=${pair%%=*}
    value=${pair#*=}
    python3 - "$package_dir/contents/config/main.xml" "$key" "$value" <<'PY'
import re, sys
path, key, value = sys.argv[1:]
text = open(path).read()
pattern = r'(<entry name="%s"[^>]*>\s*<default>)[^<]*(</default>)' % re.escape(key)
text, count = re.subn(pattern, lambda m: m.group(1) + value + m.group(2), text)
if count != 1:
    sys.exit(f"config key {key!r} not found in main.xml")
open(path, "w").write(text)
PY
done

target=root.fullRepresentationItem
[[ "$presentation" != full ]] && target=root.compactRepresentationItem
cat > "$package_dir/contents/ui/CaptureHook.qml" <<QML
import QtQuick
import org.kde.kirigami as Kirigami
Item {
    required property Item target
    visible: false
    // Popups and panels draw their background outside the applet item; paint one in so the
    // capture reads like the real thing.
    Rectangle {
        parent: target
        anchors.fill: parent
        z: -1
        color: Kirigami.Theme.backgroundColor
    }
    Timer {
        interval: $delay_ms
        running: true
        onTriggered: target.grabToImage(function(result) { result.saveToFile("$capture_path") })
    }
}
QML
# The capture grabs only this item's pixels, never other windows or desktop content.
sed -i "$ i\\    CaptureHook { target: $target }" "$package_dir/contents/ui/main.qml"
kpackagetool6 -t Plasma/Applet -i "$package_dir" >/dev/null

if [[ "$presentation" == full ]]; then
    plasmawindowed "$package_id" >"$scratch_dir/log" 2>&1 &
    window_pid=$!
else
    location=top; [[ "$presentation" == vertical ]] && location=left
    panel_id=$(qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "var p = new Panel; p.location = \"$location\"; p.height = ${PLASMA_CAPTURE_THICKNESS:-46}; p.lengthMode = \"fit\"; p.alignment = \"center\"; p.addWidget(\"$package_id\"); print(p.id);" | tail -n1)
fi
for _ in $(seq 1 $(( delay_ms / 1000 + 8 ))); do
    [[ -s "$capture_path" ]] && break
    sleep 1
done
if [[ ! -s "$capture_path" ]]; then
    [[ -f "$scratch_dir/log" ]] && cat "$scratch_dir/log" >&2
    echo "no capture produced" >&2
    exit 1
fi
mkdir -p "$(dirname "$output")"
cp "$capture_path" "$output"
echo "$output"
