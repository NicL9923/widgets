from __future__ import annotations

import json
from pathlib import Path

from device_battery import headsetcontrol

FIXTURES = Path(__file__).parent / "fixtures"


def payload(battery_status: str, level: int, **device: object) -> dict[str, object]:
    entry = {
        "status": "success",
        "device": "HyperX Cloud Alpha Wireless",
        "product": "HyperX Cloud Alpha Wireless",
        "id_vendor": "0x03f0",
        "id_product": "0x098d",
        "capabilities": ["CAP_SIDETONE", "CAP_BATTERY_STATUS"],
        "battery": {"status": battery_status, "level": level},
    }
    entry.update(device)
    return {"device_count": 1, "devices": [entry]}


def test_headset_that_is_off_is_left_out_without_an_error() -> None:
    # Captured from a real HyperX dongle with the headset switched off.
    result = headsetcontrol.parse(json.loads((FIXTURES / "headsetcontrol_off.json").read_text()))
    assert result.devices == ()
    assert result.error is None


def test_available_battery_becomes_a_headset() -> None:
    (device,) = headsetcontrol.parse(payload("BATTERY_AVAILABLE", 72)).devices
    assert (device.name, device.kind, device.percent, device.charging) == (
        "HyperX Cloud Alpha Wireless",
        "headset",
        72,
        False,
    )


def test_charging_without_a_level_keeps_charging_and_drops_the_number() -> None:
    (device,) = headsetcontrol.parse(payload("BATTERY_CHARGING", -1)).devices
    assert (device.percent, device.charging) == (None, True)


def test_available_status_with_impossible_level_fails_closed() -> None:
    result = headsetcontrol.parse(payload("BATTERY_AVAILABLE", -1))
    assert result.devices == ()
    assert result.error is not None
    assert "out of range" in result.error.message


def test_hid_errors_and_unknown_statuses_are_reported() -> None:
    for status, reason in [("BATTERY_TIMEOUT", "BATTERY_TIMEOUT"), ("BATTERY_NEW", "unrecognized")]:
        result = headsetcontrol.parse(payload(status, 50))
        assert result.devices == ()
        assert result.error is not None
        assert reason in result.error.message


def test_failed_query_on_a_battery_headset_is_reported() -> None:
    result = headsetcontrol.parse(payload("BATTERY_AVAILABLE", 50, status="failure"))
    assert result.devices == ()
    assert result.error is not None
    assert "failure" in result.error.message


def test_failed_query_on_a_headset_without_battery_is_ignored() -> None:
    result = headsetcontrol.parse(
        payload("BATTERY_AVAILABLE", 50, status="failure", capabilities=["CAP_SIDETONE"])
    )
    assert (result.devices, result.error) == ((), None)


def test_captured_headset_reading() -> None:
    # Captured from a real HyperX Cloud Alpha Wireless that was switched on.
    result = headsetcontrol.parse(json.loads((FIXTURES / "headsetcontrol_on.json").read_text()))
    (device,) = result.devices
    assert result.error is None
    assert (device.name, device.kind, device.charging) == (
        "HyperX Cloud Alpha Wireless",
        "headset",
        False,
    )
    assert 0 <= device.percent <= 100
