# macOS look for Plasma 6

`apply.sh` turns a Plasma 6.8 desktop into something close to macOS 26:

- MacTahoe dark colors, Plasma style, Kvantum app style, icons, and cursors, from
  [vinceliuice](https://github.com/vinceliuice) at pinned commits.
- The MacTahoe window decoration with close, minimize, and maximize on the left.
- A 30 px menu bar on every screen: launcher, the six [System Stats](../../system-stats/)
  modules, [Device Battery](../../device-battery/), [AI Usage](../../ai-usage/), weather,
  tray, and a "Thu Nov 19 19:23" clock.
- A floating dock on the primary screen with your existing task manager launchers.
- Magic Lamp minimize.

It snapshots the files it changes to `~/.local/share/desktop-backups/` first and prints the
restore command. `restore.sh BACKUP_DIR` puts everything back.

## What it leaves alone

- The MacTahoe global theme and SDDM login theme. Both fail to load on Plasma 6.8, which
  removed `VirtualKeyboardLoader` (MacTahoe-kde issues 21 and 22).
- The global menu. On Wayland it stays empty for Electron and most GTK apps.
- Extra KWin effects. Better Blur DX (COPR `infinality/kwin-effects-better-blur-dx`,
  Plasma 6.8 support since 2.6.0) and KDE-Rounded-Corners 0.11 add translucency and round
  bottom corners. Add them one at a time; on several monitors they cost GPU time.
- Keyboard remapping. Toshy maps Cmd shortcuts on Wayland but changes input system-wide.

`layout.js` is a Plasma shell script. `carry.py` reads settings worth keeping, such as
launchers, the weather location, and clock time zones, from the panels it replaces.
