"""The JSON contract the plasmoid renders."""

from __future__ import annotations

from dataclasses import dataclass

CONTRACT_VERSION = 1

# Kinds the plasmoid has icons for. Anything else renders as "other".
KINDS = ("headset", "headphones", "earbuds", "mouse", "keyboard", "gamepad", "speaker", "other")


@dataclass(frozen=True)
class Device:
    """One connected device with a battery reading.

    ``percent`` is None when the device reports that it is charging but not how full it is,
    or when it is asleep and no earlier reading is known. A device that reports nothing at
    all is not a Device; it is left out, because an absent reading must never render as an
    empty battery.

    ``asleep`` marks a device whose receiver is plugged in but which did not answer, like a
    wireless mouse in power-saving sleep. Its percent, if any, is the last real reading, and
    ``updated_at`` says when that reading was taken.
    """

    id: str
    name: str
    kind: str
    percent: int | None
    charging: bool
    source: str
    asleep: bool = False
    updated_at: str | None = None

    def to_json(self) -> dict[str, object]:
        return {
            "id": self.id,
            "name": self.name,
            "kind": self.kind if self.kind in KINDS else "other",
            "percent": self.percent,
            "charging": self.charging,
            "source": self.source,
            "asleep": self.asleep,
            "updatedAt": self.updated_at,
        }


@dataclass(frozen=True)
class SourceError:
    source: str
    message: str

    def to_json(self) -> dict[str, str]:
        return {"source": self.source, "message": self.message}


@dataclass(frozen=True)
class SourceResult:
    devices: tuple[Device, ...] = ()
    error: SourceError | None = None


def clamp_percent(value: float) -> int | None:
    """Round a reported level to a whole percent, rejecting values outside 0-100."""
    if value != value or value < 0 or value > 100:  # NaN or out of range
        return None
    return round(value)
