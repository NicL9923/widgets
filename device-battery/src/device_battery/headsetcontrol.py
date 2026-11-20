"""Wireless gaming headsets through HeadsetControl (https://github.com/Sapd/HeadsetControl).

Their batteries live behind vendor HID reports on the USB dongle, so neither the kernel nor
UPower sees them. HeadsetControl knows the per-vendor protocols and ships udev rules that
give the logged-in user access to the dongle.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from typing import Any

from .models import Device, SourceError, SourceResult, clamp_percent

SOURCE = "headsetcontrol"

# The dongle answers for the headset. "Unavailable" means the headset itself is off or out
# of range, which is the normal disconnected state, not an error.
_DISCONNECTED = {"BATTERY_UNAVAILABLE"}
_FAILED = {"BATTERY_ERROR", "BATTERY_TIMEOUT"}


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def parse(payload: dict[str, Any]) -> SourceResult:
    devices: list[Device] = []
    failures: list[str] = []
    for entry in payload.get("devices") or []:
        name = entry.get("product") or entry.get("device") or "Headset"
        battery = entry.get("battery")
        if entry.get("status") != "success" or not isinstance(battery, dict):
            if "CAP_BATTERY_STATUS" in (entry.get("capabilities") or []):
                failures.append(f"{name}: {entry.get('status') or 'no battery reading'}")
            continue
        status = battery.get("status")
        if status in _DISCONNECTED:
            continue
        if status in _FAILED:
            failures.append(f"{name}: {status}")
            continue
        if status not in ("BATTERY_AVAILABLE", "BATTERY_CHARGING"):
            failures.append(f"{name}: unrecognized battery status {status!r}")
            continue
        level = battery.get("level")
        percent = clamp_percent(float(level)) if isinstance(level, int | float) else None
        charging = status == "BATTERY_CHARGING"
        # Some headsets report -1 while charging. Keep the charging state, drop the number.
        if percent is None and not charging:
            failures.append(f"{name}: battery level {level!r} is out of range")
            continue
        devices.append(
            Device(
                id=f"{SOURCE}:{entry.get('id_vendor', '')}:{entry.get('id_product', '')}:"
                + _slug(name),
                name=name,
                kind="headset",
                percent=percent,
                charging=charging,
                source=SOURCE,
            )
        )
    error = SourceError(SOURCE, "; ".join(failures)) if failures else None
    return SourceResult(devices=tuple(devices), error=error)


def read(timeout: float = 5.0) -> SourceResult:
    binary = shutil.which("headsetcontrol")
    if binary is None:
        return SourceResult()  # Not installed: this machine has no supported headset.
    try:
        completed = subprocess.run(
            [binary, "--battery", "--output", "json"],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        payload = json.loads(completed.stdout)
    except subprocess.TimeoutExpired:
        return SourceResult(error=SourceError(SOURCE, "HeadsetControl timed out"))
    except ValueError:
        message = (completed.stderr or "").strip() or "HeadsetControl printed no JSON"
        return SourceResult(error=SourceError(SOURCE, message))
    if not isinstance(payload, dict):
        return SourceResult(error=SourceError(SOURCE, "HeadsetControl printed unexpected JSON"))
    return parse(payload)
