"""Command line entrypoint. Emits the JSON contract the plasmoid renders."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from collections.abc import Callable, Iterable
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path

from . import headsetcontrol, razer, upower
from .models import CONTRACT_VERSION, Device, SourceResult, clamp_percent

Reader = Callable[[], SourceResult]
# Vendor protocols first: they read the device directly, so when UPower also lists the same
# device (some kernels expose a HID battery), the direct reading wins.
READERS: tuple[Reader, ...] = (headsetcontrol.read, razer.read, upower.read)


def _normalized(name: str) -> str:
    return "".join(character for character in name.lower() if character.isalnum())


def default_cache_path() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "device-battery" / "last-readings.json"


def load_cache(path: Path) -> dict[str, dict[str, object]]:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_cache(path: Path, cache: dict[str, dict[str, object]]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
            json.dump(cache, handle)
        Path(handle.name).replace(path)
    except OSError:
        pass  # A missing cache only costs the last-known level of a sleeping device.


def remember(devices: list[Device], cache: dict[str, dict[str, object]], now: str) -> list[Device]:
    """Stamp live readings, record them, and give asleep devices their last real reading."""
    result = []
    for device in devices:
        if not device.asleep:
            device = replace(device, updated_at=now)
            if device.percent is not None:
                cache[device.id] = {
                    "percent": device.percent,
                    "charging": device.charging,
                    "updatedAt": now,
                }
        else:
            entry = cache.get(device.id)
            if not isinstance(entry, dict):
                entry = {}  # Missing or corrupt: no last reading.
            percent = entry.get("percent")
            if isinstance(percent, int | float) and isinstance(entry.get("updatedAt"), str):
                device = replace(
                    device,
                    percent=clamp_percent(float(percent)),
                    charging=entry.get("charging") is True,
                    updated_at=entry["updatedAt"],
                )
        result.append(device)
    return result


def collect(
    readers: Iterable[Reader] = READERS, cache_path: Path | None = None
) -> dict[str, object]:
    devices: list[Device] = []
    errors = []
    for reader in readers:
        try:
            result = reader()
        # One source failing in an unexpected way must never hide the others.
        except Exception as error:
            source = getattr(reader, "__module__", "unknown").rsplit(".", 1)[-1]
            errors.append({"source": source, "message": f"{type(error).__name__}: {error}"})
            continue
        seen = {_normalized(device.name) for device in devices}
        devices.extend(device for device in result.devices if _normalized(device.name) not in seen)
        if result.error is not None:
            errors.append(result.error.to_json())
    now = datetime.now(UTC).isoformat(timespec="seconds")
    if cache_path is not None:
        cache = load_cache(cache_path)
        devices = remember(devices, cache, now)
        save_cache(cache_path, cache)
    return {
        "version": CONTRACT_VERSION,
        "checkedAt": now,
        "devices": [device.to_json() for device in devices],
        "errors": errors,
    }


def render_plain(payload: dict[str, object]) -> str:
    lines = []
    for device in payload["devices"]:  # type: ignore[union-attr]
        if device["percent"] is None:
            level = "asleep" if device["asleep"] else "charging"
        else:
            level = f"{device['percent']}%"
            if device["asleep"]:
                level += f", asleep since reading at {device['updatedAt']}"
            elif device["charging"]:
                level += ", charging"
        lines.append(f"{device['name']}: {level} ({device['source']})")
    if not lines:
        lines.append("No connected devices report a battery.")
    lines.extend(
        f"{error['source']} error: {error['message']}"
        for error in payload["errors"]  # type: ignore[union-attr]
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="device-battery",
        description="Report battery levels of connected wireless devices as JSON.",
    )
    parser.add_argument(
        "--plain", action="store_true", help="Human readable output instead of JSON."
    )
    arguments = parser.parse_args(argv)
    payload = collect(cache_path=default_cache_path())
    if arguments.plain:
        print(render_plain(payload))
    else:
        json.dump(payload, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
    return 0
