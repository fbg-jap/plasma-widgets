import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLogic } from "./logic.mjs"

const L = loadLogic("dokploystatus")

const svc = (type, id, name, status) => ({ type, id, name, status })
const projects = [
    { id: "p1", name: "Shop", environments: [
        { id: "e1", name: "production", services: [
            svc("application", "a1", "web", "done"), svc("application", "a2", "worker", "error"),
            svc("compose", "c1", "stack", "running"), svc("postgres", "d1", "db", "done"),
        ] },
        { id: "e2", name: "staging", services: [] },
    ] },
    { id: "p2", name: "Blog", environments: [{ id: "e3", name: "production", services: [svc("application", "a3", "site", null)] }] },
]

test("statusKey: unknown statuses count as idle", () => {
    assert.equal(L.statusKey({ status: "error" }), "error")
    assert.equal(L.statusKey({ status: null }), "idle")
    assert.equal(L.statusKey({ status: "queued" }), "idle")
})

test("allServices and countStates", () => {
    const services = L.allServices(projects)
    assert.equal(services.length, 5)
    assert.deepEqual(L.countStates(services), { done: 2, error: 1, running: 1, idle: 1 })
})

test("groupServices: one per non-empty environment, in the given state order", () => {
    const groups = L.groupServices(projects, L.statusOrder)
    assert.deepEqual(groups.map(g => g.title), ["Shop · production", "Blog"])   // env named only when there are several
    assert.deepEqual(groups[0].services.map(s => s.name), ["worker", "stack", "db", "web"])
    assert.equal(groups[0].projectId, "p1")
    assert.equal(groups[0].environmentId, "e1")
    // The original list is left alone (QML may still be showing it).
    assert.deepEqual(projects[0].environments[0].services.map(s => s.name), ["web", "worker", "stack", "db"])
    // The order comes from the caller (main.qml's serviceStates), not a copy in logic.js.
    assert.deepEqual(L.groupServices(projects, ["done", "running", "error", "idle"])[0].services.map(s => s.name),
        ["db", "web", "stack", "worker"])
})

test("serviceUrl", () => {
    const [group] = L.groupServices(projects, L.statusOrder)
    assert.equal(L.serviceUrl("https://dokploy.example.com", group, group.services[1]),
        "https://dokploy.example.com/dashboard/project/p1/environment/e1/services/compose/c1")
})

test("freshFailures: only deployments that newly failed", () => {
    const services = L.allServices(projects)
    const first = L.freshFailures(services, null)
    assert.deepEqual(first.fresh, [])
    assert.deepEqual(first.statuses, { a1: "done", a2: "error", c1: "running", d1: "done", a3: null })
    assert.deepEqual(L.freshFailures(services, first.statuses).fresh, [])
    const second = L.freshFailures(services, { ...first.statuses, a2: "running" })
    assert.deepEqual(second.fresh.map(s => s.id), ["a2"])
})

test("panelStates", () => {
    const states = L.statusOrder.map(key => ({ key, inPanel: true }))
    assert.deepEqual(L.panelStates(states, { error: 1, done: 2 }, false).map(s => s.key), ["error", "done"])
    assert.equal(L.panelStates(states, {}, true).length, 4)
})
