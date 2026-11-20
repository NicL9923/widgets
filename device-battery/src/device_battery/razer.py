"""Razer wireless mice through the vendor HID protocol on the USB dongle.

This is the same 90-byte feature report that OpenRazer's kernel driver sends, issued from
userspace through hidraw, so it works without the out-of-tree OpenRazer module. Reading
needs read-write access to the dongle's hidraw node; ``udev/70-device-battery.rules``
grants that to the logged-in user.
"""

from __future__ import annotations

import errno
import fcntl
import os
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass, replace
from pathlib import Path

from .models import Device, SourceError, SourceResult

SOURCE = "razer"
VENDOR_ID = 0x1532
REPORT_SIZE = 90


@dataclass(frozen=True)
class Model:
    name: str
    transaction_id: int


# Only dongles verified against OpenRazer's driver tables. Add a product id here after
# checking its transaction id in openrazer/driver/razermouse_driver.c.
MODELS: dict[int, Model] = {
    0x00C1: Model("Razer Viper V3 Pro", 0x1F),
}

# Report status byte.
STATUS_BUSY = 0x01
STATUS_SUCCESS = 0x02
STATUS_FAILURE = 0x03
STATUS_TIMEOUT = 0x04  # The dongle got no answer: the mouse is off, asleep, or out of range.
STATUS_NOT_SUPPORTED = 0x05

BATTERY = (0x07, 0x80)
CHARGING = (0x07, 0x84)


class DeviceAsleepError(Exception):
    """The dongle is present but the mouse did not answer."""


def _ioc(direction: int, number: int, size: int) -> int:
    return (direction << 30) | (size << 16) | (ord("H") << 8) | number


_IOC_READ_WRITE = 3
HIDIOCSFEATURE = _ioc(_IOC_READ_WRITE, 0x06, REPORT_SIZE + 1)
HIDIOCGFEATURE = _ioc(_IOC_READ_WRITE, 0x07, REPORT_SIZE + 1)


def build_request(transaction_id: int, command: tuple[int, int], data_size: int = 0x02) -> bytes:
    report = bytearray(REPORT_SIZE)
    report[1] = transaction_id
    report[5] = data_size
    report[6], report[7] = command
    report[88] = checksum(report)
    return bytes(report)


def checksum(report: bytes | bytearray) -> int:
    """XOR of bytes 2-87: everything after the status and transaction id, before the CRC."""
    value = 0
    for byte in report[2:88]:
        value ^= byte
    return value


def parse_response(request: bytes, response: bytes) -> int:
    """Return the first data argument of a successful response.

    Raises DeviceAsleepError when the mouse did not answer and ValueError for anything
    that is not a well-formed answer to this request.
    """
    if len(response) != REPORT_SIZE:
        raise ValueError(f"expected {REPORT_SIZE} bytes, got {len(response)}")
    # Check the echoed header before trusting the status, so stray bytes never read as a
    # sleeping mouse or a battery level.
    if response[1] != request[1] or response[6:8] != request[6:8]:
        raise ValueError("response is for a different command")
    status = response[0]
    if status == STATUS_TIMEOUT:
        raise DeviceAsleepError
    if status != STATUS_SUCCESS:
        raise ValueError(f"status 0x{status:02x}")
    if response[88] != checksum(response):
        raise ValueError("bad checksum")
    return response[9]


Transport = Callable[[bytes], bytes]


# OpenRazer waits 59.9 ms between SET and GET for Viper wireless receivers
# (RAZER_VIPER_MOUSE_RECEIVER_WAIT_US in razermouse_driver.h).
def hidraw_transport(fd: int, wait: float = 0.06) -> Transport:
    def exchange(request: bytes) -> bytes:
        buffer = bytearray(b"\x00" + request)  # Report id 0.
        sent = fcntl.ioctl(fd, HIDIOCSFEATURE, buffer)
        if sent != len(buffer):
            raise ValueError(f"sent {sent} of {len(buffer)} bytes")
        time.sleep(wait)
        reply = bytearray(REPORT_SIZE + 1)
        received = fcntl.ioctl(fd, HIDIOCGFEATURE, reply)
        # The ioctl returns how many bytes it filled; the rest of the buffer is still zeros.
        return bytes(reply[1:received])

    return exchange


def query(transport: Transport, model: Model, command: tuple[int, int], attempts: int = 3) -> int:
    request = build_request(model.transaction_id, command)
    for attempt in range(attempts):
        response = transport(request)
        # A busy dongle, or one whose first relay to a just-woken mouse timed out, gets
        # another try before the mouse counts as asleep.
        if response[0] in (STATUS_BUSY, STATUS_TIMEOUT) and attempt < attempts - 1:
            time.sleep(0.05)
            continue
        return parse_response(request, response)
    raise ValueError("device stayed busy")


def read_device(transport: Transport, model: Model) -> tuple[int, bool]:
    level = query(transport, model, BATTERY)
    charging = query(transport, model, CHARGING) == 1
    return round(level * 100 / 255), charging


def find_control_nodes(sysfs: Path = Path("/sys/class/hidraw")) -> Iterator[tuple[str, int, str]]:
    """Yield (/dev/hidrawN, product id, USB port) for interface 0 of every known dongle.

    The USB port path ("5-2.4.4.3") tells two receivers of the same model apart.
    """
    for node in sorted(sysfs.glob("hidraw*")):
        try:
            uevent = (node / "device/uevent").read_text()
            interface = (node / "device").resolve().parent.name
        except OSError:
            continue
        hid_id = next((line[7:] for line in uevent.splitlines() if line.startswith("HID_ID=")), "")
        parts = hid_id.split(":")
        if len(parts) != 3 or int(parts[1], 16) != VENDOR_ID:
            continue
        product = int(parts[2], 16)
        if product in MODELS and interface.endswith(":1.0"):
            yield f"/dev/{node.name}", product, interface.rsplit(":", 1)[0]


def read(sysfs: Path = Path("/sys/class/hidraw")) -> SourceResult:
    devices: list[Device] = []
    failures: list[str] = []
    for path, product, port in find_control_nodes(sysfs):
        model = MODELS[product]
        try:
            fd = os.open(path, os.O_RDWR)
        except PermissionError:
            failures.append(f"{model.name}: no access to {path}; install the udev rule")
            continue
        except OSError as error:
            failures.append(f"{model.name}: {error.strerror}")
            continue
        device = Device(
            id=f"{SOURCE}:{product:04x}:{port}",
            name=model.name,
            kind="mouse",
            percent=None,
            charging=False,
            source=SOURCE,
        )
        try:
            percent, charging = read_device(hidraw_transport(fd), model)
        except DeviceAsleepError:
            # Dongle plugged in, mouse asleep or switched off. Keep it listed; the caller
            # fills in the last known reading.
            devices.append(replace(device, asleep=True))
            continue
        except OSError as error:
            if error.errno in (errno.ENODEV, errno.EPIPE):
                continue  # Unplugged mid-read.
            failures.append(f"{model.name}: {error.strerror}")
            continue
        except ValueError as error:
            failures.append(f"{model.name}: {error}")
            continue
        finally:
            os.close(fd)
        devices.append(replace(device, percent=percent, charging=charging))
    error = SourceError(SOURCE, "; ".join(failures)) if failures else None
    return SourceResult(devices=tuple(devices), error=error)
