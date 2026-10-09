import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLogic, isoAgo } from "./logic.mjs"

const L = loadLogic("sentrystatus")
const NOW = Date.parse("2026-10-09T12:00:00Z")

const issue = (id, project, firstSeenMinutesAgo, lastSeenMinutesAgo = firstSeenMinutesAgo, extra = {}) =>
    ({ id, project, firstSeen: isoAgo(NOW, firstSeenMinutesAgo), lastSeen: isoAgo(NOW, lastSeenMinutesAgo), ...extra })

test("isNew: first seen within 24 hours", () => {
    assert.ok(L.isNew(issue("x", "p", 23 * 60), NOW))
    assert.ok(!L.isNew(issue("x", "p", 24 * 60 + 1), NOW))
})

test("countStates: open is unresolved minus new", () => {
    assert.deepEqual(L.countStates({ new: 2, unresolved: 7, archived: 3, resolved: 40 }),
        { new: 2, open: 5, archived: 3, resolved: 40 })
    assert.deepEqual(L.countStates({ new: 3, unresolved: 2 }), { new: 3, open: 0, archived: 0, resolved: 0 })
    assert.deepEqual(L.countStates(undefined), { new: 0, open: 0, archived: 0, resolved: 0 })
})

test("groupByProject: most recently active project first, issue order kept", () => {
    const groups = L.groupByProject([
        issue("1", "shop", 600, 30), issue("2", "admin", 900, 5 * 24 * 60), issue("3", "blog", 60, 10),
        issue("4", "shop", 60, 120), issue("5", null, 60, 3 * 24 * 60),
    ])
    assert.deepEqual(groups.map(g => g.name), ["blog", "shop", "", "admin"])
    assert.deepEqual(groups[1].issues.map(i => i.id), ["1", "4"])
    assert.deepEqual(L.groupByProject([]), [])
})

test("issueUrl: the permalink when it is http(s), else built from the server", () => {
    assert.equal(L.issueUrl("https://sentry.io", "acme", { id: "9", permalink: "https://acme.sentry.io/issues/9/" }),
        "https://acme.sentry.io/issues/9/")
    assert.equal(L.issueUrl("https://sentry.example.com", "a b", { id: "9", permalink: "file:///etc/passwd" }),
        "https://sentry.example.com/organizations/a%20b/issues/9/")
    assert.equal(L.issueUrl("https://sentry.io", "acme", { id: "9" }), "https://sentry.io/organizations/acme/issues/9/")
    assert.equal(L.issuesPageUrl("https://sentry.io", "acme"), "https://sentry.io/organizations/acme/issues/")
})

test("age", () => {
    assert.deepEqual(L.age(isoAgo(NOW, 0.2), NOW), { unit: "minute", count: 1 })
    assert.deepEqual(L.age(isoAgo(NOW, 5 * 60), NOW), { unit: "hour", count: 5 })
    assert.deepEqual(L.age(isoAgo(NOW, 3 * 24 * 60), NOW), { unit: "day", count: 3 })
})

test("freshIssues: unseen issues, remembering earlier ones", () => {
    const first = L.freshIssues([issue("a", "p", 60), issue("b", "p", 60)], null)
    assert.deepEqual(first.fresh, [])
    const second = L.freshIssues([issue("b", "p", 60), issue("c", "p", 1)], first.seen)
    assert.deepEqual(second.fresh.map(i => i.id), ["c"])
    assert.deepEqual(Object.keys(second.seen).sort(), ["a", "b", "c"])
})

test("panelStates and visibleStates", () => {
    const states = ["new", "open", "archived", "resolved"].map(key => ({ key, inPanel: key !== "resolved" }))
    const counts = { new: 0, open: 2, archived: 0, resolved: 5 }
    assert.deepEqual(L.visibleStates(states, counts).map(s => s.key), ["open", "resolved"])
    assert.deepEqual(L.panelStates(states, counts, false).map(s => s.key), ["open"])
    assert.deepEqual(L.panelStates(states, counts, true).map(s => s.key), ["new", "open", "archived"])
})
