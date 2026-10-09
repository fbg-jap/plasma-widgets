import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.notification

PlasmoidItem {
    id: root

    readonly property string codeDir: Qt.resolvedUrl("../code/").toString().replace("file://", "")
    // Which docker context to show; empty means docker's current context.
    readonly property string dockerContext: Plasmoid.configuration.context.trim()

    // Containers as {id, name, project, image, stateKey, status, ports}.
    property var containers: []
    property var stateCounts: ({})
    // Previous state of each container by id, to notify only on changes; null until the first check.
    property var previousStates: null
    // Ids of containers with a start/stop/restart in progress.
    property var busyIds: ({})
    property bool loaded: false
    property date lastChecked
    property string errorText: ""
    property string actionError: ""

    // Docker exit codes that mean "stopped on purpose" (clean exit, Ctrl+C, docker stop's
    // SIGTERM, or its SIGKILL after the timeout) rather than a crash.
    readonly property var stoppedExitCodes: [0, 130, 137, 143]

    // Container states in panel order, worst first. Colours come from the Appearance settings.
    // "glyph" is used by the square style, "roundGlyph" by the rounded one.
    readonly property var containerStates: [
        { key: "failed", label: i18n("Failed"), glyph: "cross", roundGlyph: "cross", color: Plasmoid.configuration.colorFailed,
          inPanel: Plasmoid.configuration.showFailedInPanel },
        { key: "unhealthy", label: i18n("Unhealthy"), glyph: "exclamation", roundGlyph: "exclamation", color: Plasmoid.configuration.colorUnhealthy,
          inPanel: Plasmoid.configuration.showUnhealthyInPanel },
        { key: "restarting", label: i18n("Restarting"), glyph: "restart", roundGlyph: "restart", color: Plasmoid.configuration.colorRestarting,
          inPanel: Plasmoid.configuration.showRestartingInPanel },
        { key: "paused", label: i18n("Paused"), glyph: "pause", roundGlyph: "pause", color: Plasmoid.configuration.colorPaused,
          inPanel: Plasmoid.configuration.showPausedInPanel },
        { key: "stopped", label: i18n("Stopped"), glyph: "stop", roundGlyph: "stop", color: Plasmoid.configuration.colorStopped,
          inPanel: Plasmoid.configuration.showStoppedInPanel },
        { key: "running", label: i18n("Running"), glyph: "play", roundGlyph: "play", color: Plasmoid.configuration.colorRunning,
          inPanel: Plasmoid.configuration.showRunningInPanel },
    ]
    readonly property var visibleStates: containerStates.filter(st => (stateCounts[st.key] || 0) > 0)
    // Badges (in the panel, the popup and on the desktop) show the states switched on in the
    // settings, optionally including empty ones.
    readonly property var panelStates: containerStates.filter(st => st.inPanel
        && (Plasmoid.configuration.showZeroInPanel || (stateCounts[st.key] || 0) > 0))
    readonly property int problemCount: (stateCounts.failed || 0) + (stateCounts.unhealthy || 0)

    // Containers grouped by Compose project (standalone ones last), problems first within a group.
    readonly property var groups: {
        const order = containerStates.map(st => st.key)
        const byProject = {}
        containers.forEach(c => (byProject[c.project] = byProject[c.project] || []).push(c))
        return Object.keys(byProject)
            .sort((a, b) => (a === "") - (b === "") || a.localeCompare(b))
            .map(project => ({
                project: project,
                containers: byProject[project].sort((a, b) =>
                    order.indexOf(a.stateKey) - order.indexOf(b.stateKey) || a.name.localeCompare(b.name))
            }))
    }

    function stateOf(key) {
        return containerStates.find(st => st.key === key)
    }

    // White or near-black, whichever reads better on the given background colour.
    function contrastText(background) {
        const c = Qt.color(background)
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.6 ? "#202020" : "white"
    }

    function shellQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function refresh() {
        fetcher.connectSource("sh " + shellQuote(codeDir + "fetch.sh") + " " + shellQuote(dockerContext))
    }

    function runAction(container, action) {
        const busy = Object.assign({}, busyIds)
        busy[container.id] = true
        busyIds = busy
        actionError = ""
        actions.connectSource("sh " + shellQuote(codeDir + "action.sh") + " " + shellQuote(dockerContext)
            + " " + action + " " + shellQuote(container.id))
    }

    function label(labels, key) {
        const match = new RegExp("(?:^|,)" + key.replace(/\./g, "\\.") + "=([^,]*)").exec(labels || "")
        return match ? match[1] : ""
    }

    function classify(c) {
        switch (c.State) {
        case "restarting": return "restarting"
        case "paused": return "paused"
        case "running":
            return c.HealthStatus === "unhealthy" || /\(unhealthy\)/.test(c.Status) ? "unhealthy" : "running"
        case "dead": return "failed"
        case "exited": {
            const exit = /Exited \((\d+)\)/.exec(c.Status)
            return exit && !stoppedExitCodes.includes(parseInt(exit[1])) ? "failed" : "stopped"
        }
        default: return "stopped" // created, removing
        }
    }

    // "0.0.0.0:8888->80/tcp, [::]:8888->80/tcp" -> "8888→80"
    function shortPorts(ports) {
        const seen = []
        const re = /:(\d+)->(\d+)/g
        let m
        while ((m = re.exec(ports || "")) !== null) {
            const p = m[1] + "→" + m[2]
            if (!seen.includes(p)) seen.push(p)
        }
        return seen.join(", ")
    }

    function shortImage(image) {
        return image.startsWith("sha256:") ? image.slice(7, 19) : image
    }

    function apply(stdout) {
        const list = stdout.split("\n").filter(line => line.trim()).map(line => JSON.parse(line)).map(c => {
            const project = label(c.Labels, "com.docker.compose.project")
            return {
                id: c.ID,
                name: label(c.Labels, "com.docker.compose.service") || c.Names,
                fullName: c.Names,
                project: project,
                image: shortImage(c.Image),
                stateKey: classify(c),
                status: c.Status,
                ports: shortPorts(c.Ports),
            }
        })
        const counts = {}
        list.forEach(c => counts[c.stateKey] = (counts[c.stateKey] || 0) + 1)
        containers = list
        stateCounts = counts
        loaded = true
        notifyAboutProblems()
    }

    function notifyAboutProblems() {
        const isProblem = key => key === "failed" || key === "unhealthy"
        const fresh = containers.filter(c => previousStates && isProblem(c.stateKey) && previousStates[c.id] !== c.stateKey)
        const states = {}
        containers.forEach(c => states[c.id] = c.stateKey)
        previousStates = states

        if (fresh.length === 0 || !Plasmoid.configuration.notifyOnProblem) {
            return
        }
        const describe = c => i18n("%1 is %2", c.fullName, stateOf(c.stateKey).label.toLowerCase())
        if (fresh.length === 1) {
            problemNotification.title = i18n("Docker: %1", describe(fresh[0]))
            problemNotification.text = fresh[0].status
        } else {
            problemNotification.title = i18np("Docker: %1 container needs attention", "Docker: %1 containers need attention", fresh.length)
            problemNotification.text = fresh.slice(0, 4).map(describe).join("\n")
        }
        problemNotification.sendEvent()
    }

    onDockerContextChanged: {
        loaded = false
        containers = []
        stateCounts = {}
        previousStates = null
        errorText = ""
        refresh()
    }

    P5Support.DataSource {
        id: fetcher
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            root.lastChecked = new Date()
            if (data["exit code"] !== 0) {
                root.errorText = data["stderr"].trim() || i18n("docker exited with code %1", data["exit code"])
                return
            }
            try {
                root.apply(data["stdout"])
                root.errorText = ""
            } catch (e) {
                root.errorText = i18n("Could not read docker output: %1", e.message)
            }
        }
    }

    P5Support.DataSource {
        id: actions
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            const id = sourceName.split(" ").pop().replace(/'/g, "")
            const busy = Object.assign({}, root.busyIds)
            delete busy[id]
            root.busyIds = busy
            if (data["exit code"] !== 0) {
                root.actionError = data["stderr"].trim() || i18n("docker exited with code %1", data["exit code"])
            }
            root.refresh()
        }
    }

    Notification {
        id: problemNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "folder-docker"
        urgency: Notification.HighUrgency
    }

    Timer {
        interval: Plasmoid.configuration.pollInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Plasmoid.icon: "folder-docker"
    Plasmoid.status: problemCount > 0 ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

    toolTipMainText: dockerContext ? i18n("Docker (%1)", dockerContext) : i18n("Docker")
    toolTipSubText: {
        if (errorText) return errorText
        if (!loaded) return i18n("Loading…")
        if (containers.length === 0) return i18n("No containers")
        return visibleStates.map(st => i18n("%1 %2", stateCounts[st.key], st.label.toLowerCase())).join(" · ")
    }

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    // Badge symbols as vector paths on a 100×100 grid, so they're exactly centred and sharp at any
    // size (font glyphs like ▶ or ✕ sit off-centre). "stroke" paths are drawn as rounded lines,
    // "fill" paths are filled.
    readonly property var glyphPaths: ({
        check: { stroke: "M 25 52 L 43 70 L 76 32" },
        cross: { stroke: "M 30 30 L 70 70 M 70 30 L 30 70" },
        exclamation: { stroke: "M 50 22 L 50 54", fill: "M 42 72 A 8 8 0 1 0 58 72 A 8 8 0 1 0 42 72 Z" },
        wave: { stroke: "M 20 55 C 30 30, 42 30, 50 50 C 58 70, 70 70, 80 45" },
        dash: { stroke: "M 24 50 L 40 50 M 60 50 L 76 50" },
        question: { stroke: "M 37 37 C 37 21, 63 21, 63 37 C 63 49, 50 48, 50 58", fill: "M 43 74 A 7 7 0 1 0 57 74 A 7 7 0 1 0 43 74 Z" },
        arrowDown: { stroke: "M 50 24 L 50 74 M 31 55 L 50 74 L 69 55" },
        pause: { fill: "M 30 26 L 44 26 L 44 74 L 30 74 Z M 56 26 L 70 26 L 70 74 L 56 74 Z" },
        stop: { fill: "M 31 31 L 69 31 L 69 69 L 31 69 Z" },
        play: { fill: "M 36 25 L 76 50 L 36 75 Z" },
        restart: { stroke: "M 71 40 A 23 23 0 1 0 73 58", fill: "M 60 26 L 82 28 L 74 48 Z" },
        gear: { stroke: "M 50 34 A 16 16 0 1 1 49.9 34 M 50 14 L 50 24 M 50 76 L 50 86 M 14 50 L 24 50 M 76 50 L 86 50 M 25 25 L 32 32 M 68 68 L 75 75 M 75 25 L 68 32 M 25 75 L 32 68" },
    })

    // One badge symbol from glyphPaths, scaled to the item's size.
    component Glyph: Item {
        id: glyph
        property string kind
        property color color
        readonly property var paths: root.glyphPaths[kind] || ({})

        Shape {
            width: 100
            height: 100
            scale: glyph.width / 100
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: glyph.paths.stroke ? glyph.color : "transparent"
                strokeWidth: 12
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: glyph.paths.stroke || "M 0 0" }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: glyph.paths.fill ? glyph.color : "transparent"
                PathSvg { path: glyph.paths.fill || "M 0 0" }
            }
        }
    }

    // A status badge: the state's symbol on a block of its colour, then the count.
    // Square or rounded (pill-shaped), as chosen under Appearance.
    component StatusBadge: Rectangle {
        property var containerState
        property int count
        property real size
        readonly property bool rounded: Plasmoid.configuration.badgeStyle === "rounded"

        implicitHeight: size
        implicitWidth: glyphBlock.width + countLabel.implicitWidth + size * (rounded ? 0.7 : 0.5)
        radius: rounded ? height / 2 : 2
        color: Plasmoid.configuration.colorCountBackground
        border.width: rounded ? 1.5 : 1
        border.color: containerState.color

        Rectangle {
            id: glyphBlock
            width: parent.size
            height: parent.size
            radius: parent.rounded ? width / 2 : 2
            color: containerState.color

            Glyph {
                anchors.centerIn: parent
                width: parent.width * 0.7
                height: width
                kind: parent.parent.rounded ? containerState.roundGlyph : containerState.glyph
                color: root.contrastText(containerState.color)
            }
        }

        PlasmaComponents.Label {
            id: countLabel
            anchors.left: glyphBlock.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: count
            color: root.contrastText(Plasmoid.configuration.colorCountBackground)
            font.pixelSize: parent.size * 0.6
        }
    }

    // A row (or column, in a vertical panel) of status badges, optionally followed by "(of N)".
    component BadgeBar: GridLayout {
        id: bar
        property real badgeSize
        property bool vertical: false
        property var badgeStates: root.visibleStates
        property bool showTotal: false
        property bool showLogo: false
        readonly property int itemCount: badgeStates.length + (showTotal ? 1 : 0) + (showLogo ? 1 : 0)

        flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: vertical ? Math.max(itemCount, 1) : 1
        columns: vertical ? 1 : Math.max(itemCount, 1)
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing

        // Optional logo in front of the badges (panel only), chosen under Appearance.
        Kirigami.Icon {
            visible: bar.showLogo
            Layout.preferredWidth: bar.badgeSize
            Layout.preferredHeight: bar.badgeSize
            source: Plasmoid.configuration.logoIcon || Plasmoid.icon
        }

        Repeater {
            model: bar.badgeStates
            StatusBadge {
                required property var modelData
                containerState: modelData
                count: root.stateCounts[modelData.key] || 0
                size: bar.badgeSize
            }
        }

        PlasmaComponents.Label {
            visible: bar.showTotal
            text: i18n("(of %1)", root.containers.length)
            font.pixelSize: bar.badgeSize * 0.6
        }
    }

    compactRepresentation: MouseArea {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real badgeSize: Math.min(Kirigami.Units.iconSizes.smallMedium, vertical ? width : height)
        readonly property bool showTotal: Plasmoid.configuration.showTotalInPanel
        readonly property bool showBadges: root.loaded && (root.panelStates.length > 0 || showTotal)

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                root.expanded = !root.expanded
            }
        }

        Layout.minimumWidth: vertical ? 0 : (showBadges ? badges.implicitWidth : badgeSize)
        Layout.minimumHeight: vertical ? (showBadges ? badges.implicitHeight : badgeSize) : 0

        BadgeBar {
            id: badges
            anchors.centerIn: parent
            visible: compact.showBadges
            badgeStates: root.panelStates
            showTotal: compact.showTotal
            showLogo: Plasmoid.configuration.showLogo
            vertical: compact.vertical
            badgeSize: compact.badgeSize
            opacity: root.errorText ? 0.5 : 1
        }

        // Before the first successful check, or when docker can't be reached.
        Kirigami.Icon {
            anchors.centerIn: parent
            width: compact.badgeSize
            height: compact.badgeSize
            visible: !compact.showBadges
            source: Plasmoid.icon
            active: compact.containsMouse
            opacity: 0.5
        }
    }

    // One container in the popup: state dot, name, details, and start/stop/restart buttons.
    component ContainerRow: PlasmaComponents.ItemDelegate {
        id: row
        property var container
        readonly property bool busy: root.busyIds[container.id] === true
        readonly property bool active: container.stateKey === "running" || container.stateKey === "unhealthy"
            || container.stateKey === "restarting"

        Layout.fillWidth: true
        hoverEnabled: true

        PlasmaComponents.ToolTip.text: container.fullName + "\n" + container.status
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: width
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Kirigami.Units.smallSpacing
                radius: width / 2
                color: root.stateOf(row.container.stateKey).color
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: row.container.name
                    font.bold: row.container.stateKey === "failed" || row.container.stateKey === "unhealthy"
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: [row.container.image, row.container.status, row.container.ports].filter(t => t).join(" · ")
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                visible: row.busy
                running: visible
            }

            PlasmaComponents.ToolButton {
                visible: !row.busy && !row.active && row.container.stateKey !== "paused"
                icon.name: "media-playback-start"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Start %1", row.container.name)
                onClicked: root.runAction(row.container, "start")
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
            }
            PlasmaComponents.ToolButton {
                visible: !row.busy && row.active
                icon.name: "view-refresh"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Restart %1", row.container.name)
                onClicked: root.runAction(row.container, "restart")
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
            }
            PlasmaComponents.ToolButton {
                visible: !row.busy && row.active
                icon.name: "media-playback-stop"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Stop %1", row.container.name)
                onClicked: root.runAction(row.container, "stop")
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.dockerContext ? i18n("Docker · %1", root.dockerContext) : i18n("Docker")
                    elide: Text.ElideRight
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }

        footer: ColumnLayout {
            spacing: 0

            BadgeBar {
                Layout.margins: Kirigami.Units.smallSpacing
                Layout.bottomMargin: 0
                visible: root.loaded
                badgeSize: Kirigami.Units.iconSizes.small * 1.25
                badgeStates: root.panelStates
                showTotal: Plasmoid.configuration.showTotalInPanel
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                text: isNaN(root.lastChecked) ? "" : i18n("Last checked %1", root.lastChecked.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.errorText !== "" && !root.loaded
            iconName: "dialog-error"
            text: i18n("Could not reach Docker")
            explanation: root.errorText
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.loaded && root.containers.length === 0
            iconName: "folder-docker"
            text: i18n("No containers")
        }

        PlasmaComponents.ScrollView {
            id: scroll
            anchors.fill: parent
            // Long titles are elided instead of making the list scroll sideways.
            contentWidth: availableWidth
            visible: root.loaded && root.containers.length > 0

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 0

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing
                    visible: root.errorText !== "" || root.actionError !== ""
                    type: Kirigami.MessageType.Warning
                    text: root.actionError || root.errorText
                }

                Repeater {
                    model: root.groups

                    ColumnLayout {
                        id: group
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        Kirigami.ListSectionHeader {
                            Layout.fillWidth: true
                            text: i18n("%1 (%2)", group.modelData.project || i18n("Standalone containers"),
                                       group.modelData.containers.length)
                        }
                        Repeater {
                            model: group.modelData.containers
                            ContainerRow {
                                required property var modelData
                                container: modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
