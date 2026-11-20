from __future__ import annotations

from device_battery import cli
from device_battery.models import Device, SourceError, SourceResult


def device(name: str, source: str, percent: int = 50) -> Device:
    return Device(f"{source}:{name}", name, "headset", percent, False, source)


def test_first_source_wins_when_two_report_the_same_device() -> None:
    payload = cli.collect(
        [
            lambda: SourceResult(devices=(device("HyperX Cloud Alpha Wireless", "hc", 80),)),
            lambda: SourceResult(devices=(device("HyperX Cloud-Alpha wireless", "upower", 70),)),
        ]
    )
    assert [(d["source"], d["percent"]) for d in payload["devices"]] == [("hc", 80)]


def test_a_crashing_source_does_not_hide_the_others() -> None:
    def broken() -> SourceResult:
        raise RuntimeError("boom")

    payload = cli.collect(
        [
            broken,
            lambda: SourceResult(
                devices=(device("Mouse", "razer"),), error=SourceError("razer", "asleep")
            ),
        ]
    )
    assert [d["name"] for d in payload["devices"]] == ["Mouse"]
    assert payload["errors"][0]["message"] == "RuntimeError: boom"
    assert payload["errors"][1] == {"source": "razer", "message": "asleep"}


def test_unknown_kinds_render_as_other() -> None:
    odd = Device("x", "Pen", "stylus", 10, False, "upower")
    payload = cli.collect([lambda: SourceResult(devices=(odd,))])
    assert payload["devices"][0]["kind"] == "other"


NOW = "2026-11-20T01:00:00+00:00"
EARLIER = "2026-11-20T00:50:00+00:00"


def test_live_readings_are_remembered_with_their_time() -> None:
    cache: dict[str, dict[str, object]] = {}
    (live,) = cli.remember([device("Mouse", "razer", 90)], cache, NOW)
    assert live.updated_at == NOW
    assert cache["razer:Mouse"] == {"percent": 90, "charging": False, "updatedAt": NOW}


def test_sleeping_device_shows_its_last_real_reading() -> None:
    cache = {"razer:Mouse": {"percent": 88, "charging": True, "updatedAt": EARLIER}}
    asleep = Device("razer:Mouse", "Mouse", "mouse", None, False, "razer", asleep=True)
    (shown,) = cli.remember([asleep], cache, NOW)
    assert (shown.percent, shown.charging, shown.asleep, shown.updated_at) == (
        88,
        True,
        True,
        EARLIER,
    )
    assert cache["razer:Mouse"]["updatedAt"] == EARLIER  # Sleep never refreshes the reading.


def test_sleeping_device_without_a_usable_reading_has_no_level() -> None:
    asleep = Device("razer:Mouse", "Mouse", "mouse", None, False, "razer", asleep=True)
    unusable = [
        {},
        {"razer:Mouse": {"percent": "88", "updatedAt": EARLIER}},
        {"razer:Mouse": {"percent": 88}},
    ]
    for cache in unusable:
        (shown,) = cli.remember([asleep], cache, NOW)
        assert (shown.percent, shown.updated_at) == (None, None)


def test_cache_round_trips_and_tolerates_a_corrupt_file(tmp_path) -> None:
    path = tmp_path / "nested" / "last-readings.json"
    cli.save_cache(path, {"a": {"percent": 1}})
    assert cli.load_cache(path) == {"a": {"percent": 1}}
    path.write_text("{not json")
    assert cli.load_cache(path) == {}
