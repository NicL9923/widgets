# Agent Instructions

KDE Plasma 6 widgets, one per folder. Each folder is self-contained: its own applet package,
helper (where needed), tests, install script, README, and widget-specific `AGENTS.md` where
present (`ai-usage/AGENTS.md`).

| Folder | Widget | Data source |
| --- | --- | --- |
| `ai-usage/` | AI Usage: Claude Code, Codex, and Grok subscription usage. Also ships a macOS menu bar app. | Python helper over the vendor CLIs |
| `system-stats/` | System Stats: a Linux port of Stats for macOS (CPU, GPU, memory, disk, network, sensors). | KDE's `ksystemstats` through `org.kde.ksysguard.*` QML modules. No helper. |
| `device-battery/` | Device Battery: wireless headset, mouse, and Bluetooth battery levels. | Python helper over HeadsetControl, Razer hidraw, and UPower |

Read the widget's own `AGENTS.md` before changing it. `desktop/macos-look/` is a separate
script that installs a macOS-style theme and arranges these widgets into a menu bar; it
changes the live desktop, so run it only when asked and keep its snapshot and restore path
working.

## Project workflow

- Before opening a PR (skip only for typo-level changes), run an independent review of the
  full branch diff following `.github/agents/review-agent.md` using the global model policy
  in `AGENTS.global.md`, and address findings first.

## Shared standards

- **Absent is not zero.** A reading that did not arrive renders as missing, never as 0%, an
  empty battery, or a guessed value. Parsers fail closed.
- **One source failing never hides the others.** Helpers capture each source's failure as
  an error entry next to the other sources' results.
- Helpers use only the Python standard library and run from a copy installed by the
  widget's `scripts/install.sh`, so switching branches never changes an installed widget.
- Add a happy-path and an edge-case test for new pure functions. Prefer fixtures captured
  from real devices or CLIs over hand-written ones.

### QML

- Unversioned Qt 6 imports; no `import ... 2.0`.
- Size and space with `Kirigami.Units`, color with `Kirigami.Theme` roles. No hard-coded
  pixels or colors, so widgets follow the active theme. Warning thresholds map to
  `neutralTextColor`; critical ones map to `negativeTextColor`.
- Leave `preferredRepresentation` unset so Plasma picks compact in a panel and full on the
  desktop.
- Keep pure logic in a `.js` file next to the QML and test it with `node --test`.
- User-facing copy is sentence case ("Refresh now", not "Refresh Now"), plain and specific.

## Build and verify

- Set up once at the repository root: `python3 -m venv .venv`, then
  `.venv/bin/pip install -e './ai-usage[dev]' -e './device-battery[dev]'`, and
  `git config core.hooksPath .githooks` for the pre-commit format and lint hook.
- Lint and format every Python widget from the root with `.venv/bin/ruff check .` and
  `.venv/bin/ruff format .`. The shared rules are in `ruff.toml`.
- Run each Python suite from its folder: `(cd ai-usage && ../.venv/bin/python -m pytest)`.
- Run every QML logic suite: `node --test */tests/*.cjs`.
- Lint QML for syntax and type errors:
  `/usr/lib64/qt6/bin/qmllint -I /usr/lib64/qt6/qml $(find WIDGET/plasmoid -name '*.qml')`.
  Unqualified-access warnings about `root` are expected in applets.
- Verify visually with `.agents/tools/plasma-capture.sh`, which captures a temporary copy of
  any applet's popup or panel item without touching the installed one. Then check
  `journalctl --user --since "-5 min" | grep -i qml` for load errors.
