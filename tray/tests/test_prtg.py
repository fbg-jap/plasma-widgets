import pytest

from statusbadges.model import ProviderError
from statusbadges.providers.prtg import PRTGStatus

SERVER = "https://prtg.example.com"


def sensor(objid, status_raw, device="router", name="Ping", message="-", lastvalue=""):
    return {"objid": objid, "device": device, "sensor": name, "status_raw": status_raw,
            "message_raw": message, "lastvalue": lastvalue}


@pytest.fixture
def prtg(http, secrets):
    secrets[("prtg", SERVER)] = "key123"

    def table(url, params):
        if params.get("filter_status"):
            return {"sensors": [sensor(1, 5, message="Timeout"), sensor(2, 4, "nas", "Disk", "90% used", "90 %"),
                                sensor(3, 14), sensor(4, 13)]}
        return {"sensors": [sensor(i, raw) for i, raw in enumerate([5, 14, 4, 10, 13, 3, 3, 3, 7, 12, 1])]}

    http.add(SERVER + "/api/table.json", table)
    return PRTGStatus({"server": SERVER + "/"})


def test_counts_every_sensor_by_state(prtg):
    result = prtg.fetch()
    assert result.counts == {"down": 2, "warning": 1, "unusual": 1, "acknowledged": 1, "up": 3, "paused": 2,
                             "unknown": 1}
    assert result.summary == "prtg.example.com"


def test_lists_problem_sensors_grouped_worst_first(prtg):
    sections = prtg.fetch().sections
    assert [s.title for s in sections] == ["Down", "Warning", "Acknowledged"]
    down = sections[0].items
    assert [(i.id, i.title, i.subtitle, i.bold) for i in down] == [
        ("1", "router – Ping", "Timeout", True),
        ("3", "router – Ping", "", True),        # "-" means no message
    ]
    assert down[0].url == SERVER + "/sensor.htm?id=1"
    assert sections[1].items[0].subtitle == "90 % · 90% used"


def test_sends_the_key_and_asks_only_for_problems_first(prtg, http):
    prtg.fetch()
    problems, everything = http.calls
    assert problems["params"]["apitoken"] == "key123"
    assert problems["params"]["filter_status"] == [4, 5, 10, 13, 14]
    assert "filter_status" not in everything["params"]


def test_needs_a_server(secrets):
    with pytest.raises(ProviderError, match="No PRTG server"):
        PRTGStatus({}).fetch()


def test_needs_a_key(secrets):
    with pytest.raises(ProviderError, match="No API key"):
        PRTGStatus({"server": SERVER}).fetch()
