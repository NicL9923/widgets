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
# BatteryLevel 1 means "None": the device reports a real percentage. Any other value is a
# coarse level (low, normal, full...) for which UPower synthesizes a percentage, so it is not
# a reading this widget can show as a number.
_BATTERY_LEVEL_NONE = 1


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
    if _value(props, "BatteryLevel", default=_BATTERY_LEVEL_NONE) != _BATTERY_LEVEL_NONE:
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


def _failure(error: Exception) -> str:
    if isinstance(error, subprocess.CalledProcessError):
        return (error.stderr or str(error)).strip()
    return f"Could not read UPower: {error}"


# What busctl prints when a device disconnected between listing and reading. GLib's
# dispatcher answers "Object does not exist at path"; other services use UnknownObject.
_GONE = ("Object does not exist at path", "UnknownObject", "Unknown object")

_READ_ERRORS = (
    subprocess.CalledProcessError,
    subprocess.TimeoutExpired,
    ValueError,
    KeyError,
    TypeError,
)


def read(timeout: float = 5.0) -> SourceResult:
    binary = shutil.which("busctl")
    if binary is None:
        return SourceResult()
    try:
        (paths,) = _busctl(
            binary, *BUS, "org.freedesktop.UPower", "EnumerateDevices", timeout=timeout
        )
    except subprocess.CalledProcessError as error:
        # No UPower daemon is a legitimate setup, not a failure worth surfacing.
        if "was not provided by any .service files" in (error.stderr or ""):
            return SourceResult()
        return SourceResult(error=SourceError(SOURCE, _failure(error)))
    except _READ_ERRORS as error:
        return SourceResult(error=SourceError(SOURCE, _failure(error)))
    devices = []
    failures = []
    for path in paths:
        try:
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
        except subprocess.CalledProcessError as error:
            # A device that disconnected between listing and reading is simply gone.
            if any(marker in (error.stderr or "") for marker in _GONE):
                continue
            failures.append(_failure(error))
            continue
        except _READ_ERRORS as error:
            failures.append(_failure(error))
            continue
        if device is not None:
            devices.append(device)
    error = SourceError(SOURCE, "; ".join(failures)) if failures else None
    return SourceResult(devices=tuple(devices), error=error)
