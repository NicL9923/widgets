"""Razer HID protocol, checked against bytes captured from a real Viper V3 Pro dongle."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from device_battery import razer

CAPTURE = json.loads((Path(__file__).parent / "fixtures/razer_viper_v3_pro.json").read_text())
VIPER = razer.MODELS[0x00C1]


def captured(name: str) -> tuple[bytes, bytes]:
    return bytes.fromhex(CAPTURE[name]["request"]), bytes.fromhex(CAPTURE[name]["response"])


def with_status(response: bytes, status: int) -> bytes:
    return bytes([status]) + response[1:]


class FakeDongle:
    """Answers each request with the next queued response; fails on an unexpected call."""

    def __init__(self, *responses: bytes) -> None:
        self.responses = list(responses)
        self.requests: list[bytes] = []

    def __call__(self, request: bytes) -> bytes:
        self.requests.append(request)
        if not self.responses:
            raise AssertionError("unexpected request")
        return self.responses.pop(0)


@pytest.mark.parametrize("name", ["battery", "charging"])
def test_request_matches_bytes_the_dongle_accepted(name: str) -> None:
    request, _ = captured(name)
    command = razer.BATTERY if name == "battery" else razer.CHARGING
    assert razer.build_request(VIPER.transaction_id, command) == request


def test_battery_reading_scales_to_percent() -> None:
    _, battery = captured("battery")
    _, charging = captured("charging")
    dongle = FakeDongle(battery, charging)
    assert razer.read_device(dongle, VIPER) == (90, False)  # 0xe6 = 230 of 255
    assert [request[6:8] for request in dongle.requests] == [b"\x07\x80", b"\x07\x84"]


def test_charging_flag_is_read_from_first_data_byte() -> None:
    _, battery = captured("battery")
    _, charging = captured("charging")
    charging = bytearray(charging)
    charging[9] = 1
    charging[88] = razer.checksum(charging)
    assert razer.read_device(FakeDongle(battery, bytes(charging)), VIPER) == (90, True)


def test_timeout_status_means_the_mouse_is_asleep() -> None:
    request, response = captured("battery")
    with pytest.raises(razer.DeviceAsleepError):
        razer.parse_response(request, with_status(response, razer.STATUS_TIMEOUT))


@pytest.mark.parametrize(
    ("mutate", "reason"),
    [
        (lambda r: with_status(r, razer.STATUS_FAILURE), "status 0x03"),
        (lambda r: with_status(r, razer.STATUS_NOT_SUPPORTED), "status 0x05"),
        (lambda r: r[:7] + b"\x84" + r[8:], "different command"),
        (lambda r: r[:1] + b"\x3f" + r[2:], "different command"),
        # A timeout status on bytes that do not echo this request is not a sleeping mouse.
        (lambda _r: bytes([razer.STATUS_TIMEOUT]) + bytes(89), "different command"),
        (lambda r: r[:9] + b"\x01" + r[10:], "bad checksum"),
        (lambda r: r[:-1], "expected 90 bytes"),
    ],
)
def test_malformed_responses_are_rejected(mutate, reason: str) -> None:
    request, response = captured("battery")
    with pytest.raises(ValueError, match=reason):
        razer.parse_response(request, mutate(response))


def test_busy_or_just_woken_dongle_is_retried(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(razer.time, "sleep", lambda _: None)
    _, response = captured("battery")
    dongle = FakeDongle(
        with_status(response, razer.STATUS_BUSY),
        with_status(response, razer.STATUS_TIMEOUT),
        response,
    )
    assert razer.query(dongle, VIPER, razer.BATTERY) == 230


def test_mouse_that_never_answers_counts_as_asleep(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(razer.time, "sleep", lambda _: None)
    _, response = captured("battery")
    timeout = with_status(response, razer.STATUS_TIMEOUT)
    with pytest.raises(razer.DeviceAsleepError):
        razer.query(FakeDongle(timeout, timeout, timeout), VIPER, razer.BATTERY)


def make_hidraw(root: Path, name: str, hid_id: str, interface: str) -> None:
    device = root / "devices" / interface / "0003:XXXX"
    device.mkdir(parents=True)
    (device / "uevent").write_text(f"DRIVER=hid-generic\nHID_ID={hid_id}\nHID_NAME=x\n")
    node = root / "class" / name
    node.mkdir(parents=True)
    (node / "device").symlink_to(device)


def test_only_interface_zero_of_known_dongles_is_used(tmp_path: Path) -> None:
    make_hidraw(tmp_path, "hidraw4", "0003:00001532:000000C1", "5-2:1.0")
    make_hidraw(tmp_path, "hidraw5", "0003:00001532:000000C1", "5-2:1.1")
    make_hidraw(tmp_path, "hidraw6", "0003:00001532:000000FF", "5-3:1.0")  # Unknown model.
    make_hidraw(tmp_path, "hidraw7", "0003:000003F0:0000098D", "5-4:1.0")  # Not Razer.
    assert list(razer.find_control_nodes(tmp_path / "class")) == [("/dev/hidraw4", 0x00C1, "5-2")]


def test_missing_permission_is_reported(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    make_hidraw(tmp_path, "hidraw4", "0003:00001532:000000C1", "5-2:1.0")

    def denied(path: str, _flags: int) -> int:
        raise PermissionError(13, "Permission denied", path)

    monkeypatch.setattr(razer.os, "open", denied)
    result = razer.read(tmp_path / "class")
    assert result.devices == ()
    assert result.error is not None
    assert "install the udev rule" in result.error.message


def test_sleeping_mouse_stays_listed_without_a_level(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    make_hidraw(tmp_path, "hidraw4", "0003:00001532:000000C1", "5-2:1.0")
    _, response = captured("battery")
    timeout = with_status(response, razer.STATUS_TIMEOUT)
    closed: list[int] = []
    monkeypatch.setattr(razer.os, "open", lambda *_: 42)
    monkeypatch.setattr(razer.os, "close", closed.append)
    monkeypatch.setattr(razer.time, "sleep", lambda _: None)
    monkeypatch.setattr(razer, "hidraw_transport", lambda _: FakeDongle(timeout, timeout, timeout))
    result = razer.read(tmp_path / "class")
    (device,) = result.devices
    assert (device.id, device.asleep, device.percent) == ("razer:00c1:5-2", True, None)
    assert result.error is None
    assert closed == [42]


def test_short_hid_reply_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    request, response = captured("battery")
    monkeypatch.setattr(razer.time, "sleep", lambda _: None)

    def ioctl(_fd: int, op: int, buffer: bytearray) -> int:
        if op == razer.HIDIOCSFEATURE:
            return len(buffer)
        buffer[1:11] = response[:10]  # The kernel filled only the first ten bytes.
        return 11

    monkeypatch.setattr(razer.fcntl, "ioctl", ioctl)
    with pytest.raises(ValueError, match="expected 90 bytes"):
        razer.parse_response(request, razer.hidraw_transport(3)(request))


def test_two_receivers_of_one_model_get_distinct_ids(tmp_path: Path) -> None:
    make_hidraw(tmp_path, "hidraw4", "0003:00001532:000000C1", "5-2:1.0")
    make_hidraw(tmp_path, "hidraw9", "0003:00001532:000000C1", "3-1:1.0")
    ports = [port for _, _, port in razer.find_control_nodes(tmp_path / "class")]
    assert ports == ["5-2", "3-1"]
