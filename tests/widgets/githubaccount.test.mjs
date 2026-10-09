import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLogic, isoAgo } from "./logic.mjs"

const L = loadLogic("githubaccount")

const pr = (number, rollup, draft = false) => ({
    title: `PR ${number}`, url: `https://github.com/o/r/pull/${number}`, number, isDraft: draft,
    repository: { nameWithOwner: "o/r" },
    commits: { nodes: rollup === undefined ? [] : [{ commit: { statusCheckRollup: rollup && { state: rollup } } }] },
})

const fetched = {
    notifications: [{ id: "1", unread: true }, { id: "2", unread: false }],
    graphql: { data: {
        viewer: {
            login: "octo",
            pullRequests: { totalCount: 25, nodes: [pr(1, "FAILURE"), pr(2, "PENDING", true), pr(3, null), pr(4)] },
            repositories: { nodes: [
                { nameWithOwner: "o/r", url: "https://github.com/o/r", pushedAt: "2026-10-01T00:00:00Z",
                  defaultBranchRef: { target: { statusCheckRollup: { state: "SUCCESS" } } } },
                { nameWithOwner: "o/empty", url: "https://github.com/o/empty", pushedAt: "2026-10-01T00:00:00Z",
                  defaultBranchRef: null },
            ] },
        },
        reviews: { issueCount: 3, nodes: [{ title: "Review me", url: "https://github.com/o/r/pull/9" }, {}] },
    } },
}

test("parse", () => {
    const p = L.parse(fetched)
    assert.equal(p.login, "octo")
    assert.equal(p.prCount, 25)                         // GitHub's total, not the 4 listed
    assert.equal(p.reviewCount, 3)
    assert.equal(p.reviews.length, 1)                   // entries without a URL are skipped
    assert.deepEqual(p.pullRequests.map(x => x.ci), ["FAILURE", "PENDING", null, null])
    assert.deepEqual(p.pullRequests[1], { title: "PR 2", url: "https://github.com/o/r/pull/2", number: 2, isDraft: true,
                                          repo: "o/r", ci: "PENDING" })
    assert.deepEqual(p.repos.map(r => [r.name, r.ci]), [["o/r", "SUCCESS"], ["o/empty", null]])
})

test("ciCategory and ciCounts", () => {
    assert.equal(L.ciCategory("SUCCESS"), "passing")
    assert.equal(L.ciCategory("FAILURE"), "failing")
    assert.equal(L.ciCategory("ERROR"), "failing")
    assert.equal(L.ciCategory("PENDING"), "running")
    assert.equal(L.ciCategory("EXPECTED"), "running")
    assert.equal(L.ciCategory(null), "")
    const p = L.parse(fetched)
    assert.deepEqual(L.ciCounts(p.pullRequests, p.repos), { failing: 1, running: 1, passing: 1 })
})

test("notificationUrl", () => {
    const n = (type, url) => ({ subject: { type, url }, repository: { html_url: "https://github.com/o/r" } })
    assert.equal(L.notificationUrl(n("PullRequest", "https://api.github.com/repos/o/r/pulls/7")), "https://github.com/o/r/pull/7")
    assert.equal(L.notificationUrl(n("Issue", "https://api.github.com/repos/o/r/issues/3")), "https://github.com/o/r/issues/3")
    assert.equal(L.notificationUrl(n("Commit", "https://api.github.com/repos/o/r/commits/abc")), "https://github.com/o/r/commit/abc")
    assert.equal(L.notificationUrl(n("Release", "https://api.github.com/repos/o/r/releases/1")), "https://github.com/o/r/releases")
    assert.equal(L.notificationUrl(n("CheckSuite", null)), "https://github.com/notifications")
})

test("freshNotifications: unread ones not seen before", () => {
    const first = L.freshNotifications(fetched.notifications, null)
    assert.deepEqual(first.fresh, [])
    assert.deepEqual(first.seen, { 1: true, 2: true })
    const later = [{ id: "1", unread: true }, { id: "2", unread: true }, { id: "3", unread: true }, { id: "4", unread: false }]
    const second = L.freshNotifications(later, first.seen)
    assert.deepEqual(second.fresh.map(n => n.id), ["3"])
    assert.deepEqual(Object.keys(second.seen).sort(), ["1", "2", "3", "4"])   // read ones too
})

test("age", () => {
    const now = Date.parse("2026-10-09T12:00:00Z")
    assert.deepEqual(L.age(isoAgo(now, 0), now), { unit: "minute", count: 1 })
    assert.deepEqual(L.age(isoAgo(now, 90), now), { unit: "hour", count: 2 })
    assert.deepEqual(L.age(isoAgo(now, 36 * 60), now), { unit: "day", count: 2 })
})
