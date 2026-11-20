#!/usr/bin/env bash
# Give Plasma 6 a macOS look: MacTahoe theme parts, a menu bar with this repo's widgets on
# every screen, and a dock on every screen. Snapshots the current setup first;
# restore.sh puts it back. Safe to re-run.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
# The directory KDE actually reads, which is not always ~/.config.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
layout_file="plasma-org.kde.plasma.desktop-appletsrc"
backup="${XDG_DATA_HOME:-$HOME/.local/share}/desktop-backups/pre-macos-look-$(date +%Y%m%d-%H%M%S)"
# Pinned upstream commits, so a re-run installs what was tested. Bump after checking them.
declare -A pins=(
  [MacTahoe-kde]=cbf6a1f71b591d143184855d62f6272ce533e7c3
  [MacTahoe-icon-theme]=839848b9a8a38a92a6936e30c4abe35cc6f2546d
)
CONFIG_FILES=(kdeglobals kwinrc plasma-org.kde.plasma.desktop-appletsrc plasmashellrc kcminputrc
  kglobalshortcutsrc plasmarc kwinrulesrc kscreenlockerrc gtk-3.0 gtk-4.0 gtkrc gtkrc-2.0
  xsettingsd Kvantum krunnerrc)

[[ -f "$config_dir/$layout_file" ]] || { echo "no Plasma layout in $config_dir; is this a Plasma session?" >&2; exit 1; }
session_dir="$(python3 "$here/session-config-dir.py")"
if [[ "$session_dir" != "$(realpath -m "$config_dir")" ]]; then
  echo "this shell uses $config_dir but Plasma reads $session_dir; nothing changed" >&2
  exit 1
fi

# Read everything that can fail before changing anything.
carry="$(python3 "$here/carry.py" "$config_dir/$layout_file")"
python3 -c 'import json, sys; json.loads(sys.argv[1])' "$carry"
layout="$(cat "$here/layout.js")"

echo "==> Saving current setup to $backup"
mkdir -p "$backup/config"
# restore.sh deletes paths listed in "absent", so it also undoes files this script creates.
: > "$backup/absent"
for name in "${CONFIG_FILES[@]}"; do
  if [[ -e "$config_dir/$name" ]]; then
    cp -a "$config_dir/$name" "$backup/config/"
  else
    echo "$name" >> "$backup/absent"
  fi
done
echo "$config_dir" > "$backup/config-dir"
cmp -s "$config_dir/$layout_file" "$backup/config/$layout_file" \
  || { echo "snapshot of $layout_file failed; nothing changed" >&2; exit 1; }

echo "==> Installing Kvantum and the widgets"
rpm -q kvantum >/dev/null 2>&1 || sudo dnf install -y kvantum
"$repo_root/system-stats/scripts/install.sh" >/dev/null
"$repo_root/device-battery/scripts/install.sh" >/dev/null
"$repo_root/ai-usage/scripts/install.sh" >/dev/null

echo "==> Installing MacTahoe theme parts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for repo in "${!pins[@]}"; do
  git -C "$work" init -q "$repo"
  git -C "$work/$repo" fetch -q --depth 1 "https://github.com/vinceliuice/$repo.git" "${pins[$repo]}"
  git -C "$work/$repo" checkout -q FETCH_HEAD
done
(cd "$work/MacTahoe-kde" && ./install.sh -c dark >/dev/null)
(cd "$work/MacTahoe-icon-theme" && ./install.sh >/dev/null && cd cursors && ./install.sh >/dev/null)
# Plasma's cursor list only scans ~/.icons for user cursor themes.
mkdir -p "$HOME/.icons"
ln -sfn "$HOME/.local/share/icons/MacTahoe-dark-cursors" "$HOME/.icons/MacTahoe-dark-cursors"

echo "==> Applying the theme"
# MacTahoe's global theme and SDDM theme fail to load on Plasma 6.8 (MacTahoe-kde issues
# 21 and 22), so apply the parts individually and leave the login screen alone.
plasma-apply-colorscheme MacTahoeDark
plasma-apply-desktoptheme MacTahoe-Dark
plasma-apply-cursortheme MacTahoe-dark-cursors
/usr/libexec/plasma-changeicons MacTahoe-dark
kvantummanager --set MacTahoeDark
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__MacTahoe-Dark
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false
qdbus-qt6 org.kde.KWin /KWin reconfigure

echo "==> Spotlight: KRunner centered on screen, on Meta+S"
kwriteconfig6 --file krunnerrc --group General --key FreeFloating true
pkill -x krunner || true  # it reads krunnerrc at start and is restarted on demand
"$here/spotlight-shortcut.py" add

echo "==> Building the menu bars and docks"
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "var CARRY = $carry;
$layout"

echo
echo "Done. To undo: $here/restore.sh $backup"
