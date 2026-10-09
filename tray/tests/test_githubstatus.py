from statusbadges.providers.githubstatus import PAGE, GitHubStatus


def component(cid, name, status="operational", group=False):
    return {"id": cid, "name": name, "status": status, "group": group}


def summary(components, incidents=(), maintenances=(), description="All Systems Operational"):
    return {"status": {"description": description}, "components": list(components),
            "incidents": list(incidents), "scheduled_maintenances": list(maintenances)}


def test_counts_components_by_status(http):
    http.add(PAGE + "/api/v2/summary.json", summary([
        component("1", "Git Operations"),
        component("2", "Actions", "partial_outage"),
        component("3", "Pages", "degraded_performance"),
        component("4", "API Requests"),
    ]))
    result = GitHubStatus({}).fetch()
    assert result.counts == {"operational": 2, "partial_outage": 1, "degraded_performance": 1}
    assert result.summary == "All Systems Operational"
    [components] = result.sections
    assert components.title == "Components"
    assert [(i.title, i.subtitle, i.state) for i in components.items][1] == ("Actions", "Partial outage", "partial_outage")


def test_skips_groups_and_the_visit_link(http):
    http.add(PAGE, summary([
        component("1", "Git Operations"),
        component("g", "Copilot", group=True),
        component("v", "Visit www.githubstatus.com for more information"),
    ]))
    result = GitHubStatus({}).fetch()
    assert result.counts == {"operational": 1}
    assert [i.title for i in result.sections[0].items] == ["Git Operations"]


def test_lists_incidents_and_maintenance_in_progress(http):
    http.add(PAGE, summary(
        [component("1", "Actions", "major_outage")],
        incidents=[{"id": "i1", "name": "Actions are failing", "status": "investigating", "impact": "critical",
                    "shortlink": "https://stspg.io/abc"}],
        maintenances=[{"id": "m1", "name": "Database upgrade", "status": "in_progress", "impact": "maintenance"},
                      {"id": "m2", "name": "Later upgrade", "status": "scheduled", "impact": "maintenance"}],
        description="Major System Outage"))
    result = GitHubStatus({}).fetch()
    incidents, components = result.sections
    assert incidents.title == "Active incidents"
    assert [(i.title, i.state, i.url, i.bold) for i in incidents.items] == [
        ("Actions are failing", "major_outage", "https://stspg.io/abc", True),
        ("Database upgrade", "under_maintenance", PAGE, True),
    ]
    assert incidents.items[0].subtitle == "investigating · critical impact"
    assert result.summary == "Major System Outage"
