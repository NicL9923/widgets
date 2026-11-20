#!/usr/bin/env bash
# Put back a setup saved by apply.sh: restore.sh ~/.local/share/desktop-backups/pre-macos-look-…
set -euo pipefail

backup="${1:?usage: restore.sh BACKUP_DIR (apply.sh prints it)}"
layout_file="plasma-org.kde.plasma.desktop-appletsrc"
[[ -f "$backup/config/$layout_file" ]] || { echo "no Plasma layout in $backup/config" >&2; exit 1; }
config_dir="$(cat "$backup/config-dir" 2>/dev/null || echo "${XDG_CONFIG_HOME:-$HOME/.config}")"

# Restore into the directory the running Plasma session reads, or not at all.
session_dir="$(python3 "$(dirname "${BASH_SOURCE[0]}")/session-config-dir.py")"
if [[ "$session_dir" != "$(realpath -m "$config_dir")" ]]; then
  echo "snapshot is for $config_dir but Plasma reads $session_dir; nothing changed" >&2
  exit 1
fi
# The appearance commands below must read the restored files too.
export XDG_CONFIG_HOME="$config_dir"

stage="$(mktemp -d "$config_dir/.restore-stage.XXXXXX")"
rollback="$(mktemp -d "$config_dir/.restore-rollback.XXXXXX")"
installed=()
restored=false
stopped=false

finish() {
  set +e
  if [[ "$restored" != true ]]; then
    echo "Restore failed; putting the previous files back." >&2
    for name in "${installed[@]}"; do
      rm -rf "${config_dir:?}/$name"
    done
    for item in "$rollback"/* "$rollback"/.[!.]*; do
      [[ -e "$item" ]] && mv "$item" "$config_dir/"
    done
  fi
  # Whatever happened above, never leave the desktop without a shell.
  if [[ "$stopped" == true && "$restored" != true ]] \
      && ! systemctl --user start plasma-plasmashell.service; then
    echo "plasmashell did not start even with the previous files." >&2
    echo "Check $config_dir, then run: systemctl --user start plasma-plasmashell.service" >&2
  fi
  rm -rf "$stage"
  if [[ "$restored" == true || -z "$(ls -A "$rollback")" ]]; then
    rm -rf "$rollback"
  else
    echo "Some previous files could not be moved back; they are in $rollback" >&2
  fi
}
trap finish EXIT

# Stage the snapshot next to the live config first, so a failed copy changes nothing.
cp -a "$backup/config/." "$stage/"

# plasmashell rewrites its layout on exit, so stop it before swapping files.
stopped=true
systemctl --user stop plasma-plasmashell.service
for item in "$stage"/*; do
  name="$(basename "$item")"
  if [[ -e "$config_dir/$name" ]]; then
    mv "$config_dir/$name" "$rollback/"
  fi
  mv "$item" "$config_dir/"
  installed+=("$name")
done
# Files that did not exist before apply.sh ran are moved aside, not kept.
if [[ -f "$backup/absent" ]]; then
  while IFS= read -r name; do
    if [[ -n "$name" && -e "$config_dir/$name" ]]; then
      mv "$config_dir/$name" "$rollback/"
    fi
  done < "$backup/absent"
fi
# Only a shell that starts counts as restored. Otherwise the exit handler puts the previous
# files back and starts the shell with them.
systemctl --user start plasma-plasmashell.service
restored=true

# Push the restored appearance into the running session.
scheme="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
[[ -n "$scheme" ]] && plasma-apply-colorscheme "$scheme" || true
cursor="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)"
plasma-apply-cursortheme "${cursor:-breeze_cursors}" || true
icons="$(kreadconfig6 --file kdeglobals --group Icons --key Theme)"
"${PLASMA_CHANGEICONS:-/usr/libexec/plasma-changeicons}" "${icons:-breeze}" || true
qdbus-qt6 org.kde.KWin /KWin reconfigure || true
echo "Restored $backup. Log out and back in to refresh every running app's style."
