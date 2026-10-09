from statusbadges.providers import registry
from statusbadges.providers.bugsink import BugsinkStatus
from statusbadges.providers.githubaccount import GitHubAccount
from statusbadges.providers.prtg import PRTGStatus


def test_every_provider_is_registered():
    assert set(registry.providers) == {"githubstatus", "githubaccount", "prtg", "docker", "bugsink", "dokploy",
                                        "runner", "sentry"}


def test_every_provider_is_complete():
    for kind, cls in registry.providers.items():
        assert cls.kind == kind
        assert cls.name and cls.description and cls.default_interval > 0
        keys = [s.key for s in cls.states]
        assert keys and len(keys) == len(set(keys)), f"{kind} has duplicate or no states"
        for s in cls.states:
            assert s.color.startswith("#") and len(s.color) == 7, f"{kind}.{s.key} colour {s.color}"
            assert 0 <= s.severity <= 3


def test_setting_falls_back_to_the_field_default():
    provider = BugsinkStatus({"max_pages": ""})
    assert provider.setting("max_pages") == 10
    assert BugsinkStatus({"max_pages": 3}).setting("max_pages") == 3
    assert provider.setting("not_a_field") == ""


def test_server_is_trimmed():
    assert PRTGStatus({"server": "  https://prtg.example.com/ "}).server == "https://prtg.example.com"
    assert PRTGStatus({}).server == ""


def test_problem_states_are_warning_or_worse():
    assert PRTGStatus.problem_states() == {"down", "warning", "unusual"}


def test_problem_states_can_be_overridden():
    assert GitHubAccount.problem_states() == {"ci_failing", "reviews", "notifications"}
