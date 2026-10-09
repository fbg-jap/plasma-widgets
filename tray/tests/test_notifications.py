"""Which items notify: WidgetObject.notify_new_problems, with the Qt controller faked."""
import pytest

from statusbadges.model import Item, Result, Section

app = pytest.importorskip("statusbadges.app")


class FakeController:
    def __init__(self):
        self.sent = []

    def notify(self, title, text):
        self.sent.append((title, text))


def result(*offline):
    return Result({}, [Section("Runners", [Item(i, i, state="offline") for i in offline])])


def widget(kind):
    controller = FakeController()
    return app.WidgetObject(controller, {"id": "w", "kind": kind}), controller.sent


def test_a_runner_that_goes_offline_again_notifies_again():
    w, sent = widget("runner")
    for check in [(), ("r1",), (), ("r1",)]:   # first check never notifies; then offline, back, offline
        w.notify_new_problems(result(*check))
    assert [text for _, text in sent] == ["r1", "r1"]


def test_an_issue_that_reopens_does_not_notify_again():
    w, sent = widget("sentry")
    issues = lambda *ids: Result({}, [Section("Shop", [Item(i, i, state="new") for i in ids])])
    for check in [(), ("1",), (), ("1",)]:
        w.notify_new_problems(issues(*check))
    assert [text for _, text in sent] == ["1"]
