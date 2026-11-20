#!/usr/bin/env bash
# Put back a setup saved by apply.sh: restore.sh ~/.local/share/desktop-backups/pre-macos-look-…
set -euo pipefail

backup="${1:?usage: restore.sh BACKUP_DIR (apply.sh prints it)}"
[[ -d "$backup/config" ]] || { echo "no config snapshot in $backup" >&2; exit 1; }

# plasmashell rewrites its layout on exit, so stop it before restoring the files.
systemctl --user stop plasma-plasmashell.service
for item in "$backup/config"/*; do
  name="$(basename "$item")"
  rm -rf "$HOME/.config/$name"
  cp -a "$item" "$HOME/.config/$name"
done
systemctl --user start plasma-plasmashell.service

# Push the restored appearance into the running session.
scheme="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
[[ -n "$scheme" ]] && plasma-apply-colorscheme "$scheme" || true
cursor="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)"
plasma-apply-cursortheme "${cursor:-breeze_cursors}" || true
icons="$(kreadconfig6 --file kdeglobals --group Icons --key Theme)"
/usr/libexec/plasma-changeicons "${icons:-breeze}" || true
qdbus-qt6 org.kde.KWin /KWin reconfigure
echo "Restored $backup. Log out and back in to refresh every running app's style."
