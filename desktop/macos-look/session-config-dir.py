#!/usr/bin/env python3
"""Print the config directory the Plasma session reads, resolved to an absolute path.

Reads XDG_CONFIG_HOME from the systemd user manager's environment over D-Bus, which returns
raw strings. `systemctl show-environment` shell-escapes values with spaces, so it is not
used. Falls back to ~/.config when the variable is unset.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

busctl = shutil.which("busctl")
if busctl is None:
    sys.exit("busctl not found")
completed = subprocess.run(
    [
        busctl,
        "--user",
        "--json=short",
        "get-property",
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        "Environment",
    ],
    capture_output=True,
    text=True,
    check=True,
)
environment = dict(
    entry.split("=", 1) for entry in json.loads(completed.stdout)["data"] if "=" in entry
)
configured = environment.get("XDG_CONFIG_HOME")
path = Path(configured) if configured else Path("~/.config").expanduser()
print(path.resolve())
