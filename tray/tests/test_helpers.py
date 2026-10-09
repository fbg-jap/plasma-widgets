"""httpjson, process and config: the small modules every provider leans on."""
import io
import json
import sys
import urllib.error

import pytest

from statusbadges import config, httpjson, process
from statusbadges.model import ProviderError


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def test_request_builds_the_url_and_decodes_json(monkeypatch):
    seen = {}

    def urlopen(req, timeout):
        seen.update(url=req.full_url, method=req.get_method(), data=req.data, headers=dict(req.header_items()))
        return FakeResponse(b'{"ok": true}')

    monkeypatch.setattr(httpjson.urllib.request, "urlopen", urlopen)
    assert httpjson.request("https://x.test/api?a=1", params={"b": [1, 2]}, headers={"X-Key": "k"}) == {"ok": True}
    assert seen["url"] == "https://x.test/api?a=1&b=1&b=2"
    assert seen["method"] == "GET" and seen["data"] is None
    assert seen["headers"]["X-key"] == "k"

    httpjson.request("https://x.test/api", body={"id": 1})
    assert seen["method"] == "POST" and json.loads(seen["data"]) == {"id": 1}


def test_request_returns_none_for_an_empty_body(monkeypatch):
    monkeypatch.setattr(httpjson.urllib.request, "urlopen", lambda req, timeout: FakeResponse(b""))
    assert httpjson.request("https://x.test") is None


@pytest.mark.parametrize("error, message", [
    (urllib.error.HTTPError("u", 401, "Unauthorized", {}, None), "PRTG rejected the API key (401). Check the key in the settings."),
    (urllib.error.HTTPError("u", 403, "Forbidden", {}, None), "PRTG rejected the API key (403). Check the key in the settings."),
    (urllib.error.HTTPError("u", 500, "Oops", {}, None), "PRTG returned HTTP 500"),
    (urllib.error.URLError("Name or service not known"), "Could not reach x.test: Name or service not known"),
])
def test_request_turns_errors_into_messages(monkeypatch, error, message):
    def urlopen(req, timeout):
        raise error

    monkeypatch.setattr(httpjson.urllib.request, "urlopen", urlopen)
    with pytest.raises(ProviderError) as e:
        httpjson.request("https://x.test/api", auth_name="PRTG")
    assert str(e.value) == message


def test_request_rejects_non_json(monkeypatch):
    monkeypatch.setattr(httpjson.urllib.request, "urlopen", lambda req, timeout: FakeResponse(b"<html>"))
    with pytest.raises(ProviderError, match="isn't JSON"):
        httpjson.request("https://x.test", auth_name="Bugsink")


def test_process_run():
    assert process.run([sys.executable, "-c", "print('hi')"]) == "hi\n"


def test_process_run_reports_stderr_and_exit_codes():
    with pytest.raises(ProviderError, match="^boom$"):
        process.run([sys.executable, "-c", "import sys; sys.exit('boom')"])
    with pytest.raises(ProviderError, match="exited with code 3"):
        process.run([sys.executable, "-c", "import sys; sys.exit(3)"])


def test_process_run_reports_a_missing_tool():
    with pytest.raises(ProviderError, match="not installed or not on PATH"):
        process.run(["status-badges-no-such-tool"])


def test_process_run_times_out():
    with pytest.raises(ProviderError, match="did not answer within 1 seconds"):
        process.run([sys.executable, "-c", "import time; time.sleep(5)"], timeout=1)


def test_config_round_trip(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "PATH", tmp_path / "sub" / "config.json")
    assert config.load() == config.DEFAULTS
    widget = config.new_widget("prtg", "PRTG Status", 120)
    config.save({"widgets": [widget], "badgeStyle": "rounded"})
    loaded = config.load()
    assert loaded["widgets"] == [widget] and loaded["badgeStyle"] == "rounded"
    assert loaded["startAtLogin"] is False                  # defaults fill in missing keys
    assert not (tmp_path / "sub" / "config.tmp").exists()


def test_config_survives_a_corrupt_file(tmp_path, monkeypatch):
    path = tmp_path / "config.json"
    path.write_text("{not json", encoding="utf-8")
    monkeypatch.setattr(config, "PATH", path)
    assert config.load() == config.DEFAULTS


def test_new_widgets_get_unique_ids():
    ids = {config.new_widget("docker", "Docker", 15)["id"] for _ in range(50)}
    assert len(ids) == 50
