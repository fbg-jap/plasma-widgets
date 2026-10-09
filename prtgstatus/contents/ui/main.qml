import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.notification

PlasmoidItem {
    id: root

    readonly property string scriptPath: Qt.resolvedUrl("../code/fetch.sh").toString().replace("file://", "")
    readonly property string serverUrl: Plasmoid.configuration.serverUrl.trim().replace(/\/+$/, "")

    property var down: []
    property var acknowledged: []
    property var warning: []
    property var unusual: []
    property var seenDownIds: null
    property bool loaded: false
    property date lastChecked
    property string errorText: ""
    property bool loading: false

    readonly property bool allGood: loaded && down.length === 0 && warning.length === 0 && unusual.length === 0

    readonly property color downColor: Kirigami.Theme.negativeTextColor
    readonly property color warningColor: Kirigami.Theme.neutralTextColor
    // PRTG shows "unusual" in orange, between warning yellow and down red.
    readonly property color unusualColor: Qt.tint(Kirigami.Theme.neutralTextColor,
        Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.5))
    readonly property color okColor: Kirigami.Theme.positiveTextColor

    function shellQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function refresh() {
        if (!serverUrl) {
            return
        }
        loading = true
        executable.exec("sh " + shellQuote(scriptPath) + " " + shellQuote(serverUrl))
    }

    function sensorUrl(sensor) {
        return serverUrl + "/sensor.htm?id=" + sensor.objid
    }

    function apply(data) {
        const sensors = data.sensors
        down = sensors.filter(s => s.status_raw === 5 || s.status_raw === 14)
        acknowledged = sensors.filter(s => s.status_raw === 13)
        warning = sensors.filter(s => s.status_raw === 4)
        unusual = sensors.filter(s => s.status_raw === 10)
        loaded = true
        notifyAboutNewDown()
    }

    function notifyAboutNewDown() {
        const fresh = down.filter(s => seenDownIds && !seenDownIds[s.objid])
        const seen = {}
        down.forEach(s => seen[s.objid] = true)
        seenDownIds = seen

        if (fresh.length === 0 || !Plasmoid.configuration.notifyOnDown) {
            return
        }
        if (fresh.length === 1) {
            downNotification.title = i18n("PRTG: %1 is down", fresh[0].sensor)
            downNotification.text = fresh[0].device + (fresh[0].message_raw ? "\n" + fresh[0].message_raw : "")
        } else {
            downNotification.title = i18np("PRTG: %1 sensor went down", "PRTG: %1 sensors went down", fresh.length)
            downNotification.text = fresh.slice(0, 4).map(s => s.device + " – " + s.sensor).join("\n")
        }
        downNotification.sendEvent()
    }

    onServerUrlChanged: {
        loaded = false
        seenDownIds = null
        errorText = ""
        refresh()
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        function exec(cmd) {
            connectSource(cmd)
        }

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            root.loading = false
            root.lastChecked = new Date()
            if (data["exit code"] !== 0) {
                const stderr = data["stderr"].trim()
                root.errorText = stderr.includes("error: 401")
                    ? i18n("PRTG rejected the API key (401). Check the key stored in your keyring.")
                    : stderr || i18n("Fetch failed with code %1", data["exit code"])
                return
            }
            try {
                root.apply(JSON.parse(data["stdout"]))
                root.errorText = ""
            } catch (e) {
                root.errorText = i18n("Could not read PRTG response: %1", e.message)
            }
        }
    }

    Notification {
        id: downNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "network-server"
        urgency: Notification.HighUrgency
    }

    Timer {
        interval: Plasmoid.configuration.pollInterval * 60 * 1000
        running: root.serverUrl !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Plasmoid.icon: "network-server"
    Plasmoid.status: down.length > 0 ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("PRTG Status")
    toolTipSubText: {
        if (!serverUrl) return i18n("No server configured")
        if (errorText) return errorText
        if (!loaded) return i18n("Loading…")
        if (allGood) return i18n("All sensors OK")
        return [
            i18n("%1 down", down.length),
            i18n("%1 warning", warning.length),
            i18n("%1 unusual", unusual.length),
            i18n("%1 acknowledged", acknowledged.length),
        ].join(" · ")
    }

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            enabled: root.serverUrl !== ""
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: i18n("Open PRTG Alarms")
            icon.name: "internet-web-browser"
            enabled: root.serverUrl !== ""
            onTriggered: Qt.openUrlExternally(root.serverUrl + "/alarms.htm")
        }
    ]

    // A coloured pill with a number, used in the panel.
    component CountPill: Rectangle {
        property string value
        property real size

        implicitHeight: size
        implicitWidth: Math.max(size, pillLabel.implicitWidth + Kirigami.Units.smallSpacing * 2)
        radius: size / 2

        PlasmaComponents.Label {
            id: pillLabel
            anchors.centerIn: parent
            text: parent.value
            color: "white"
            font.bold: true
            font.pixelSize: parent.size * 0.7
        }
    }

    compactRepresentation: MouseArea {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real pillSize: Math.min(Kirigami.Units.iconSizes.smallMedium, vertical ? width : height)

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                root.expanded = !root.expanded
            }
        }

        Layout.minimumWidth: vertical ? 0 : pills.implicitWidth
        Layout.minimumHeight: vertical ? pills.implicitHeight : 0

        GridLayout {
            id: pills
            anchors.centerIn: parent
            flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: compact.vertical ? 4 : 1
            columns: compact.vertical ? 1 : 4
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: compact.pillSize
                Layout.preferredHeight: compact.pillSize
                source: Plasmoid.icon
                active: compact.containsMouse
                opacity: root.errorText || !root.loaded ? 0.5 : 1
                visible: !root.loaded || root.allGood || root.errorText !== ""
            }
            CountPill {
                size: compact.pillSize
                visible: root.loaded && root.down.length > 0
                color: root.downColor
                value: root.down.length
            }
            CountPill {
                size: compact.pillSize
                visible: root.loaded && root.warning.length > 0
                color: root.warningColor
                value: root.warning.length
            }
            CountPill {
                size: compact.pillSize
                visible: root.loaded && root.unusual.length > 0
                color: root.unusualColor
                value: root.unusual.length
            }
        }

        // Small green dot on the icon when everything is up.
        Rectangle {
            visible: root.allGood && !root.errorText
            width: compact.pillSize * 0.4
            height: width
            radius: width / 2
            x: pills.x + compact.pillSize - width
            y: pills.y + compact.pillSize - height
            color: root.okColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
        }
    }

    // One sensor in the popup: status dot, "device – sensor" and the PRTG message.
    component SensorRow: PlasmaComponents.ItemDelegate {
        property var sensor
        property color dotColor

        Layout.fillWidth: true
        onClicked: Qt.openUrlExternally(root.sensorUrl(sensor))

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: width
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Kirigami.Units.smallSpacing
                radius: width / 2
                color: dotColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: sensor.device + " – " + sensor.sensor
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: [sensor.lastvalue, sensor.message_raw].filter(t => t && t !== "-").join(" · ")
                    visible: text !== ""
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    // A section header plus its sensors; hidden when the group is empty.
    component SensorGroup: ColumnLayout {
        id: group
        property string title
        property var sensors: []
        property color dotColor

        Layout.fillWidth: true
        spacing: 0
        visible: sensors.length > 0

        Kirigami.ListSectionHeader {
            Layout.fillWidth: true
            text: i18n("%1 (%2)", title, sensors.length)
        }
        Repeater {
            model: sensors
            SensorRow {
                required property var modelData
                sensor: modelData
                dotColor: group.dotColor
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.serverUrl ? root.serverUrl.replace(/^https?:\/\//, "") : i18n("PRTG Status")
                    elide: Text.ElideRight
                }

                PlasmaComponents.ToolButton {
                    icon.name: "internet-web-browser"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Open PRTG alarms")
                    enabled: root.serverUrl !== ""
                    onClicked: Qt.openUrlExternally(root.serverUrl + "/alarms.htm")
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    enabled: root.serverUrl !== "" && !root.loading
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }

        footer: PlasmaComponents.Label {
            padding: Kirigami.Units.smallSpacing
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            visible: text !== ""
            text: isNaN(root.lastChecked) ? "" : i18n("Last checked %1", root.lastChecked.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: !root.serverUrl
            iconName: "configure"
            text: i18n("No PRTG server configured")
            helpfulAction: QQC2.Action {
                text: i18n("Configure…")
                icon.name: "configure"
                onTriggered: Plasmoid.internalAction("configure").trigger()
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.serverUrl !== "" && root.errorText !== "" && !root.loaded
            iconName: "dialog-error"
            text: i18n("Could not reach PRTG")
            explanation: root.errorText
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.allGood && root.acknowledged.length === 0
            iconName: "checkmark"
            text: i18n("All sensors OK")
        }

        PlasmaComponents.ScrollView {
            id: scroll
            anchors.fill: parent
            visible: root.loaded && !(root.allGood && root.acknowledged.length === 0)

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 0

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing
                    visible: root.errorText !== ""
                    type: Kirigami.MessageType.Warning
                    text: root.errorText
                }

                SensorGroup { title: i18n("Down"); sensors: root.down; dotColor: root.downColor }
                SensorGroup { title: i18n("Warning"); sensors: root.warning; dotColor: root.warningColor }
                SensorGroup { title: i18n("Unusual"); sensors: root.unusual; dotColor: root.unusualColor }
                SensorGroup { title: i18n("Acknowledged"); sensors: root.acknowledged; dotColor: Kirigami.Theme.disabledTextColor }
            }
        }
    }
}
