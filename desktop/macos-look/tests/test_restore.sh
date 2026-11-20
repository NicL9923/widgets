#!/usr/bin/env bash
# Exercise restore.sh against a throwaway config directory with every desktop command
# stubbed, so it never touches the real session: bash tests/test_restore.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

setup() {
  work="$(mktemp -d)"
  export HOME="$work/home"
  mkdir -p "$HOME/.config" "$work/bin" "$work/backup/config"
  cfg="$HOME/.config"
  echo "$cfg" > "$work/backup/config-dir"
  echo old-layout > "$cfg/plasma-org.kde.plasma.desktop-appletsrc"
  echo old-globals > "$cfg/kdeglobals"
  echo created-by-apply > "$cfg/Kvantum"
  echo saved-layout > "$work/backup/config/plasma-org.kde.plasma.desktop-appletsrc"
  echo saved-globals > "$work/backup/config/kdeglobals"
  echo Kvantum > "$work/backup/absent"
  : > "$work/calls"
  # systemctl logs each call; STUB_START_FAILS makes every "start" fail.
  cat > "$work/bin/systemctl" <<STUB
#!/usr/bin/env bash
echo "systemctl \$*" >> "$work/calls"
[[ "\$*" == *show-environment* ]] && exit 0
[[ "\$*" == *start* && -n "\${STUB_START_FAILS:-}" ]] && exit 1
exit 0
STUB
  for tool in kreadconfig6 plasma-apply-colorscheme plasma-apply-cursortheme qdbus-qt6 changeicons; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/$tool"
  done
  chmod +x "$work/bin"/*
  export PATH="$work/bin:$PATH" PLASMA_CHANGEICONS="$work/bin/changeicons"
  unset XDG_CONFIG_HOME STUB_START_FAILS
}

check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

setup
"$here/restore.sh" "$work/backup" >/dev/null 2>&1
check "restores saved files" '[[ "$(cat "$cfg/plasma-org.kde.plasma.desktop-appletsrc")" == saved-layout && "$(cat "$cfg/kdeglobals")" == saved-globals ]]'
check "removes files apply created" '[[ ! -e "$cfg/Kvantum" ]]'
check "starts plasmashell" 'grep -q "start plasma-plasmashell" "$work/calls"'
check "leaves no temp dirs" '[[ -z "$(ls -A "$cfg" | grep restore-)" ]]'
rm -rf "$work"

setup
chmod 000 "$work/backup/config/kdeglobals"
"$here/restore.sh" "$work/backup" >/dev/null 2>&1 || true
check "unreadable snapshot changes nothing" '[[ "$(cat "$cfg/plasma-org.kde.plasma.desktop-appletsrc")" == old-layout && -e "$cfg/Kvantum" ]]'
check "unreadable snapshot never stops plasmashell" '! grep -q "stop" "$work/calls"'
chmod 644 "$work/backup/config/kdeglobals"
rm -rf "$work"

setup
STUB_START_FAILS=1 "$here/restore.sh" "$work/backup" >/dev/null 2>&1 || true
check "failed start retries the shell" '[[ "$(grep -c "start plasma-plasmashell" "$work/calls")" -ge 2 ]]'
check "failed start keeps the previous files" '[[ -n "$(ls "$cfg"/.restore-rollback.*/ 2>/dev/null)" ]]'
rm -rf "$work"

setup
echo /somewhere/else > "$work/backup/config-dir"
"$here/restore.sh" "$work/backup" >/dev/null 2>&1 || true
check "snapshot for another config dir changes nothing" '[[ "$(cat "$cfg/kdeglobals")" == old-globals ]] && ! grep -q stop "$work/calls"'
rm -rf "$work"

exit $failures
