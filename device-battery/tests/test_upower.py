from __future__ import annotations

import subprocess

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
        {"BatteryLevel": 3},  # Coarse "low": UPower's percentage is synthesized.
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


def busctl_fake(responses: dict[str, object]):
    """Answer busctl calls by object path; raise for anything unexpected."""

    def call(_binary: str, *arguments: str, **_options: float) -> object:
        path = arguments[1]
        if path not in responses:
            raise AssertionError(f"unexpected busctl call for {path}")
        answer = responses[path]
        if isinstance(answer, Exception):
            raise answer
        return answer

    return call


def test_one_vanished_or_failing_device_does_not_hide_the_others(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    gone = "/org/freedesktop/UPower/devices/mouse_gone"
    broken = "/org/freedesktop/UPower/devices/keyboard_broken"
    monkeypatch.setattr(upower.shutil, "which", lambda _: "/usr/bin/busctl")
    monkeypatch.setattr(
        upower,
        "_busctl",
        busctl_fake(
            {
                "/org/freedesktop/UPower": [[gone, PATH, broken]],
                gone: subprocess.CalledProcessError(
                    1,
                    "busctl",
                    stderr="Call failed: Object does not exist at path “/org/.../mouse_gone”",
                ),
                PATH: [props()],
                broken: subprocess.CalledProcessError(1, "busctl", stderr="Access denied"),
            }
        ),
    )
    result = upower.read()
    assert [device.name for device in result.devices] == ["Powerbeats Pro"]
    assert result.error is not None
    assert result.error.message == "Access denied"
