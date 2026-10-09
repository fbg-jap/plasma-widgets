import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLogic } from "./logic.mjs"

const L = loadLogic("githubstatus")

const summary = {
    status: { indicator: "minor", description: "Minor Service Outage" },
    components: [
        { id: "1", name: "Git Operations", status: "operational" },
        { id: "2", name: "Actions", status: "degraded_performance" },
        { id: "g", name: "Copilot", status: "operational", group: true },
        { id: "v", name: "Visit www.githubstatus.com for more information", status: "operational" },
        { id: "3", name: "Pages", status: "operational" },
    ],
    incidents: [{ id: "i1", name: "Actions are slow" }],
    scheduled_maintenances: [{ id: "m1", status: "in_progress" }, { id: "m2", status: "scheduled" }],
}

test("parseSummary skips groups and the Visit link, keeps maintenance in progress", () => {
    const parsed = L.parseSummary(summary)
    assert.equal(parsed.indicator, "minor")
    assert.equal(parsed.summary, "Minor Service Outage")
    assert.deepEqual(parsed.components.map(c => c.name), ["Git Operations", "Actions", "Pages"])
    assert.deepEqual(parsed.incidents.map(i => i.id), ["i1"])
    assert.deepEqual(parsed.maintenances.map(m => m.id), ["m1"])
})

test("countStates and visibleComponents", () => {
    const components = L.parseSummary(summary).components
    assert.deepEqual(L.countStates(components), { operational: 2, degraded_performance: 1 })
    assert.equal(L.visibleComponents(components, true).length, 3)
    assert.deepEqual(L.visibleComponents(components, false).map(c => c.name), ["Actions"])
})

test("indicatorChanged: not on the first check, nor when unchanged", () => {
    assert.ok(!L.indicatorChanged("unknown", "none"))
    assert.ok(!L.indicatorChanged("none", "none"))
    assert.ok(L.indicatorChanged("none", "major"))
    assert.ok(L.indicatorChanged("major", "none"))
})

test("panelStates", () => {
    const states = ["major_outage", "operational"].map(key => ({ key, inPanel: true }))
    assert.deepEqual(L.panelStates(states, { operational: 11 }, false).map(s => s.key), ["operational"])
    assert.equal(L.panelStates(states, { operational: 11 }, true).length, 2)
})
