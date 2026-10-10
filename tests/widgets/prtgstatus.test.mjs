import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLogic } from "./logic.mjs"

const L = loadLogic("prtgstatus")

test("stateOf maps every PRTG status code", () => {
    const expected = { 1: "unknown", 2: "unknown", 3: "up", 4: "warning", 5: "down", 6: "unknown", 7: "paused",
                       8: "paused", 9: "paused", 10: "unusual", 11: "paused", 12: "paused", 13: "acknowledged", 14: "down" }
    for (const [code, key] of Object.entries(expected)) {
        assert.equal(L.stateOf(Number(code)), key, `code ${code}`)
    }
    assert.equal(L.stateOf(99), "up")                  // unknown codes count as up, as before
})

test("countStates and total", () => {
    const counts = L.countStates([5, 14, 4, 10, 13, 3, 3, 3, 7, 12, 1].map((status_raw, objid) => ({ objid, status_raw })))
    assert.deepEqual(counts, { down: 2, warning: 1, unusual: 1, acknowledged: 1, up: 3, paused: 2, unknown: 1 })
    assert.equal(L.total(counts), 11)
    assert.equal(L.total({}), 0)
})

test("splitProblems", () => {
    const sensors = [5, 4, 14, 13, 10, 3].map((status_raw, objid) => ({ objid, status_raw }))
    const p = L.splitProblems(sensors)
    assert.deepEqual(p.down.map(s => s.objid), [0, 2])
    assert.deepEqual(p.warning.map(s => s.objid), [1])
    assert.deepEqual(p.acknowledged.map(s => s.objid), [3])
    assert.deepEqual(p.unusual.map(s => s.objid), [4])
})

test("sensorUrl", () => {
    assert.equal(L.sensorUrl("https://prtg.example.com", { objid: 2001 }), "https://prtg.example.com/sensor.htm?id=2001")
})

test("freshDown: only sensors that newly went down", () => {
    const down = [{ objid: 1 }, { objid: 2 }]
    const first = L.freshDown(down, null)
    assert.deepEqual(first.fresh, [])
    assert.deepEqual(first.seen, { 1: true, 2: true })
    const second = L.freshDown([{ objid: 2 }, { objid: 3 }], first.seen)
    assert.deepEqual(second.fresh, [{ objid: 3 }])
    assert.deepEqual(second.seen, { 2: true, 3: true })  // 1 recovered: down again later counts as new
})

test("panelStates and visibleStates", () => {
    const states = Object.keys(L.stateCodes).map(key => ({ key, inPanel: key !== "paused" }))
    const counts = { down: 1, paused: 4, up: 9 }
    assert.deepEqual(L.visibleStates(states, counts).map(s => s.key), ["down", "paused", "up"])
    assert.deepEqual(L.panelStates(states, counts, false).map(s => s.key), ["down", "up"])
    assert.equal(L.panelStates(states, counts, true).length, 6)
})

test("extraStates and extraCodes: only switched-on unknown, paused and up", () => {
    const on = ["down", "warning", "paused", "up"]
    const states = Object.keys(L.stateCodes).map(key => ({ key, inPanel: on.includes(key) }))
    assert.deepEqual(L.extraStates(states).map(s => s.key), ["paused", "up"])
    assert.equal(L.extraCodes(states), "7,8,9,11,12,3")
    assert.equal(L.extraCodes(states.map(st => ({ ...st, inPanel: false }))), "")
})

test("splitExtra", () => {
    const sensors = [1, 7, 3, 12, 6, 3].map((status_raw, objid) => ({ objid, status_raw }))
    const g = L.splitExtra(sensors)
    assert.deepEqual(g.unknown.map(s => s.objid), [0, 4])
    assert.deepEqual(g.paused.map(s => s.objid), [1, 3])
    assert.deepEqual(g.up.map(s => s.objid), [2, 5])
})

test("toggled adds or removes a collapsed group", () => {
    assert.deepEqual(L.toggled([], "up"), ["up"])
    assert.deepEqual(L.toggled(["down", "up"], "up"), ["down"])
    assert.deepEqual(L.toggled(["down"], "paused"), ["down", "paused"])
})
