from __future__ import annotations

import pytest

from device_battery import upower


def props(**values: object) -> dict[str, dict[str, object]]:
    base: dict[str, object] = {
        "Model": "Powerbeats Pro",
        "Serial": "BC:37:D3:1C:38:78",
        "Type": 19,
        "PowerSupply": False,
        "IsPresent": True,
        "Percentage": 60.0,
        "State": 2,
        "BatteryLevel": 1,
    }
    base.update(values)
    return {key: {"type": "x", "data": value} for key, value in base.items()}


PATH = "/org/freedesktop/UPower/devices/headphones_dev_BC_37_D3_1C_38_78"


def test_bluetooth_headphones_are_read() -> None:
    device = upower.parse_device(PATH, props())
    assert device is not None
    assert (device.name, device.kind, device.percent, device.charging) == (
        "Powerbeats Pro",
        "headphones",
        60,
        False,
    )


def test_charging_states_set_charging() -> None:
    for state in (1, 5):
        device = upower.parse_device(PATH, props(State=state))
        assert device is not None
        assert device.charging


@pytest.mark.parametrize(
    "override",
    [
        {"PowerSupply": True},  # The computer's own battery.
        {"Type": 1},  # Line power.
        {"IsPresent": False},
        {"BatteryLevel": 0},  # Unknown: the device has not reported yet.
        {"Percentage": 140.0},
        {"Percentage": "60"},
    ],
)
def test_entries_without_a_real_peripheral_reading_are_skipped(override) -> None:
    assert upower.parse_device(PATH, props(**override)) is None


def test_missing_power_supply_flag_is_not_assumed_to_be_a_peripheral() -> None:
    values = props()
    del values["PowerSupply"]
    assert upower.parse_device(PATH, values) is None
