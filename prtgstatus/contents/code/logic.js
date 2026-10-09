.pragma library
// The PRTG Status widget's logic, kept free of Plasma and i18n so it can be unit-tested
// (tests/widgets/prtgstatus.test.mjs). main.qml imports it as Logic.

// PRTG's status_raw codes per state, in the order PRTG's status bar shows them.
var stateCodes = {
    down: [5, 14],           // Down, Down (partial)
    acknowledged: [13],
    warning: [4],
    unusual: [10],
    unknown: [1, 2, 6],
    paused: [7, 8, 9, 11, 12],
    up: [3],
}

function shellQuote(s) {
    return "'" + s.replace(/'/g, "'\\''") + "'"
}

// A status_raw code -> its state key. Codes PRTG adds later count as "up", like the widget always did.
function stateOf(code) {
    return Object.keys(stateCodes).find(key => stateCodes[key].includes(code)) || "up"
}

// fetch.sh's "all" table -> sensors per state key
function countStates(sensors) {
    const counts = {}
    sensors.forEach(s => {
        const key = stateOf(s.status_raw)
        counts[key] = (counts[key] || 0) + 1
    })
    return counts
}

// fetch.sh's "problems" table -> {down, acknowledged, warning, unusual}
function splitProblems(sensors) {
    const inState = key => sensors.filter(s => stateCodes[key].includes(s.status_raw))
    return { down: inState("down"), acknowledged: inState("acknowledged"), warning: inState("warning"),
             unusual: inState("unusual") }
}

function sensorUrl(serverUrl, sensor) {
    return serverUrl + "/sensor.htm?id=" + sensor.objid
}

// Down sensors not down at the last check, and the ids to remember. Nothing is fresh on the
// first check (seenIds null).
function freshDown(down, seenIds) {
    const fresh = down.filter(s => seenIds && !seenIds[s.objid])
    const seen = {}
    down.forEach(s => seen[s.objid] = true)
    return { fresh: fresh, seen: seen }
}

function total(counts) {
    return Object.values(counts).reduce((sum, n) => sum + n, 0)
}

// The badge states to show: those switched on in the settings (st.inPanel) with sensors in
// them, or all switched-on ones when showZero is set.
function panelStates(states, counts, showZero) {
    return states.filter(st => st.inPanel && (showZero || (counts[st.key] || 0) > 0))
}

function visibleStates(states, counts) {
    return states.filter(st => (counts[st.key] || 0) > 0)
}
