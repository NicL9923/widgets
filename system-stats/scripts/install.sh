#!/usr/bin/env bash
# Install the System Stats applet. It reads KDE's own ksystemstats, so there is no helper.
set -euo pipefail

widget_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
applet_id="com.nicl9923.systemstats"

command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 not found (install plasma-workspace)" >&2; exit 1; }
busctl --user status org.kde.ksystemstats1 >/dev/null 2>&1 \
  || echo "    ksystemstats is not running; install ksystemstats (Fedora: dnf install ksystemstats)"

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$applet_id"; then
  kpackagetool6 -t Plasma/Applet -u "${widget_root}/plasmoid"
else
  kpackagetool6 -t Plasma/Applet -i "${widget_root}/plasmoid"
fi
echo "Add one System Stats widget per module from: right-click the panel > Add Widgets."
echo "Pick the module (CPU, GPU, memory, disk, network, sensors) in each widget's settings."
