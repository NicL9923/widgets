#!/usr/bin/env bash
# Put back a setup saved by apply.sh: restore.sh ~/.local/share/desktop-backups/pre-macos-look-…
set -euo pipefail

backup="${1:?usage: restore.sh BACKUP_DIR (apply.sh prints it)}"
layout_file="plasma-org.kde.plasma.desktop-appletsrc"
[[ -f "$backup/config/$layout_file" ]] || { echo "no Plasma layout in $backup/config" >&2; exit 1; }
config_dir="$(cat "$backup/config-dir" 2>/dev/null || echo "${XDG_CONFIG_HOME:-$HOME/.config}")"

# Stage the snapshot next to the live config first, so a failed copy changes nothing.
stage="$(mktemp -d "$config_dir/.restore-stage.XXXXXX")"
rollback="$(mktemp -d "$config_dir/.restore-rollback.XXXXXX")"
restored=false
finish() {
  if [[ "$restored" != true ]]; then
    echo "Restore failed; putting the previous files back." >&2
    for item in "$rollback"/*; do
      [[ -e "$item" ]] || continue
      rm -rf "$config_dir/$(basename "$item")"
      mv "$item" "$config_dir/"
    done
  fi
  rm -rf "$stage" "$rollback"
  # Whatever happened, never leave the desktop without a shell.
  systemctl --user start plasma-plasmashell.service
}
trap finish EXIT
cp -a "$backup/config/." "$stage/"

# plasmashell rewrites its layout on exit, so stop it before swapping files.
systemctl --user stop plasma-plasmashell.service
for item in "$stage"/*; do
  name="$(basename "$item")"
  [[ -e "$config_dir/$name" ]] && mv "$config_dir/$name" "$rollback/"
  mv "$item" "$config_dir/"
done
# Files that did not exist before apply.sh ran are moved aside, not kept.
if [[ -f "$backup/absent" ]]; then
  while IFS= read -r name; do
    [[ -n "$name" && -e "$config_dir/$name" ]] && mv "$config_dir/$name" "$rollback/"
  done < "$backup/absent"
fi
restored=true
systemctl --user start plasma-plasmashell.service

# Push the restored appearance into the running session.
scheme="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
[[ -n "$scheme" ]] && plasma-apply-colorscheme "$scheme" || true
cursor="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)"
plasma-apply-cursortheme "${cursor:-breeze_cursors}" || true
icons="$(kreadconfig6 --file kdeglobals --group Icons --key Theme)"
/usr/libexec/plasma-changeicons "${icons:-breeze}" || true
qdbus-qt6 org.kde.KWin /KWin reconfigure || true
echo "Restored $backup. Log out and back in to refresh every running app's style."
