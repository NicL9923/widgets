#!/usr/bin/env python3
"""Print the settings of the current panel widgets as JSON for layout.js.

Reads ~/.config/plasma-org.kde.plasma.desktop-appletsrc and returns the first configured
copy of each widget type: {pluginId: {group: {key: value}}}. Known list-valued keys become
arrays, since Plasma's scripting API would otherwise store them as one string.
"""

import json
import re
import sys
from pathlib import Path

LIST_KEYS = {"launchers", "selectedTimeZones", "enabledCalendarPlugins"}
GROUPS = {"General", "Appearance", "Location", "Units"}


def parse(text: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current = None
    for line in text.splitlines():
        if line.startswith("["):
            current = line
            sections.setdefault(current, {})
        elif current is not None and "=" in line:
            key, value = line.split("=", 1)
            sections[current][key] = value
    return sections


def main() -> None:
    path = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else (Path.home() / ".config/plasma-org.kde.plasma.desktop-appletsrc")
    )
    sections = parse(path.read_text())
    plugins = {}
    for header, values in sections.items():
        match = re.fullmatch(r"(\[Containments\]\[\d+\]\[Applets\]\[\d+\])", header)
        if match and "plugin" in values:
            plugins[match.group(1)] = values["plugin"]
    carry: dict[str, dict[str, dict[str, object]]] = {}
    for prefix, plugin in plugins.items():
        if plugin in carry:
            continue
        groups = {}
        for group in GROUPS:
            values = sections.get(f"{prefix}[Configuration][{group}]")
            if not values:
                continue
            # Escaped values round-trip badly through the scripting API; let those reset.
            groups[group] = {
                key: value.split(",") if key in LIST_KEYS and value else value
                for key, value in values.items()
                if "\\" not in value
            }
        if groups:
            carry[plugin] = groups
    json.dump(carry, sys.stdout)


if __name__ == "__main__":
    main()
