"""Peripheral batteries UPower already knows about: Bluetooth devices, Logitech receivers,
and anything else the kernel exposes as a power_supply with ``scope=Device``."""

from __future__ import annotations

import json
import shutil
import subprocess
from typing import Any

from .models import Device, SourceError, SourceResult, clamp_percent

SOURCE = "upower"
BUS = ("org.freedesktop.UPower", "/org/freedesktop/UPower")

# org.freedesktop.UPower.Device Type values.
_KINDS = {
    5: "mouse",
    6: "keyboard",
    12: "gamepad",
    17: "headset",
    18: "speaker",
    19: "headphones",
    21: "headphones",
}
_LINE_POWER = 1
_STATE_CHARGING = 1
_STATE_PENDING_CHARGE = 5
# BatteryLevel 1 means "None": the device reports a percentage, not coarse levels.
_BATTERY_LEVEL_UNKNOWN = 0


def _value(props: dict[str, Any], key: str, default: Any = None) -> Any:
    entry = props.get(key)
    if isinstance(entry, dict) and "data" in entry:
        return entry["data"]
    return default


def parse_device(path: str, props: dict[str, Any]) -> Device | None:
    """Turn one UPower device's properties into a Device, or None if it is not a
    present peripheral with a real reading."""
    if _value(props, "PowerSupply", default=True):
        return None  # The computer's own battery or a UPS.
    if _value(props, "Type") == _LINE_POWER:
        return None
    if not _value(props, "IsPresent", default=False):
        return None
    if _value(props, "BatteryLevel") == _BATTERY_LEVEL_UNKNOWN:
        return None
    raw = _value(props, "Percentage")
    if not isinstance(raw, int | float):
        return None
    percent = clamp_percent(float(raw))
    if percent is None:
        return None
    name = (_value(props, "Model") or "").strip() or (_value(props, "Vendor") or "").strip()
    state = _value(props, "State")
    return Device(
        id="upower:" + (_value(props, "Serial") or path.rsplit("/", 1)[-1]),
        name=name or "Unknown device",
        kind=_KINDS.get(_value(props, "Type"), "other"),
        percent=percent,
        charging=state in (_STATE_CHARGING, _STATE_PENDING_CHARGE),
        source=SOURCE,
    )


def _busctl(binary: str, *arguments: str, timeout: float) -> Any:
    completed = subprocess.run(
        [binary, "--system", "--json=short", "call", *arguments],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True,
    )
    return json.loads(completed.stdout)["data"]


def read(timeout: float = 5.0) -> SourceResult:
    binary = shutil.which("busctl")
    if binary is None:
        return SourceResult()
    try:
        (paths,) = _busctl(
            binary, *BUS, "org.freedesktop.UPower", "EnumerateDevices", timeout=timeout
        )
        devices = []
        for path in paths:
            (props,) = _busctl(
                binary,
                BUS[0],
                path,
                "org.freedesktop.DBus.Properties",
                "GetAll",
                "s",
                "org.freedesktop.UPower.Device",
                timeout=timeout,
            )
            device = parse_device(path, props)
            if device is not None:
                devices.append(device)
    except subprocess.CalledProcessError as error:
        # No UPower daemon is a legitimate setup, not a failure worth surfacing.
        if "was not provided by any .service files" in (error.stderr or ""):
            return SourceResult()
        return SourceResult(error=SourceError(SOURCE, (error.stderr or str(error)).strip()))
    except (subprocess.TimeoutExpired, ValueError, KeyError, TypeError) as error:
        return SourceResult(error=SourceError(SOURCE, f"Could not read UPower: {error}"))
    return SourceResult(devices=tuple(devices))
