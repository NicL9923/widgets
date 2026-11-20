#!/usr/bin/env python3
"""Add or remove Meta+S as a KRunner shortcut, keeping KRunner's other shortcuts.

kglobalaccel keeps shortcuts in memory and writes kglobalshortcutsrc itself, so editing that
file has no effect while the session runs. This changes them over D-Bus instead.

Usage: spotlight-shortcut.py add|remove
"""

import re
import shutil
import subprocess
import sys

META_S = 0x10000000 | 0x53  # Qt::META | Qt::Key_S
ACTION = "['org.kde.krunner.desktop', '_launch', 'KRunner', 'Launch KRunner']"
gdbus = shutil.which("gdbus")


def call(method: str, *args: str) -> str:
    if gdbus is None:
        sys.exit("gdbus not found")
    return subprocess.run(
        [
            gdbus,
            "call",
            "--session",
            "-d",
            "org.kde.kglobalaccel",
            "-o",
            "/kglobalaccel",
            "-m",
            f"org.kde.KGlobalAccel.{method}",
            *args,
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("add", "remove"):
        sys.exit(__doc__)
    current = call("shortcutKeys", ACTION)
    # Each key sequence prints as a struct of four ints: ([150994993, 0, 0, 0],)
    keys = [[int(n) for n in seq.split(",")] for seq in re.findall(r"\[([\d, ]+)\]", current)]
    keys = [k for k in keys if k[0] != META_S]
    if sys.argv[1] == "add":
        keys.append([META_S, 0, 0, 0])
    value = ", ".join("([" + ", ".join(map(str, k)) + "],)" for k in keys)
    call("setForeignShortcutKeys", ACTION, f"@a(ai) [{value}]")


if __name__ == "__main__":
    main()
