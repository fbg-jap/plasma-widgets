import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.notification

PlasmoidItem {
    id: root

    readonly property string pageUrl: "https://www.githubstatus.com"
    readonly property string apiUrl: pageUrl + "/api/v2/summary.json"

    // none | minor | major | critical | maintenance | unknown
    property string indicator: "unknown"
    property string summary: i18n("Checking GitHub status…")
    property var components: []
    property var incidents: []
    property var maintenances: []
    property date lastChecked
    property string errorText: ""
    property bool loading: false

    readonly property var visibleComponents: Plasmoid.configuration.showOperational
        ? components
        : components.filter(c => c.status !== "operational")

    function indicatorColor(ind) {
        switch (ind) {
        case "none": return Kirigami.Theme.positiveTextColor
        case "minor": return Kirigami.Theme.neutralTextColor
        case "major":
        case "critical": return Kirigami.Theme.negativeTextColor
        case "maintenance": return Kirigami.Theme.activeTextColor
        default: return Kirigami.Theme.disabledTextColor
        }
    }

    function componentColor(status) {
        switch (status) {
        case "operational": return indicatorColor("none")
        case "degraded_performance": return indicatorColor("minor")
        case "partial_outage":
        case "major_outage": return indicatorColor("major")
        case "under_maintenance": return indicatorColor("maintenance")
        default: return indicatorColor("unknown")
        }
    }

    function componentLabel(status) {
        switch (status) {
        case "operational": return i18n("Operational")
        case "degraded_performance": return i18n("Degraded performance")
        case "partial_outage": return i18n("Partial outage")
        case "major_outage": return i18n("Major outage")
        case "under_maintenance": return i18n("Under maintenance")
        default: return status
        }
    }

    function formatTime(iso) {
        return new Date(iso).toLocaleString(Qt.locale(), Locale.ShortFormat)
    }

    function refresh() {
        loading = true
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return
            }
            loading = false
            lastChecked = new Date()
            if (xhr.status !== 200) {
                errorText = xhr.status ? i18n("HTTP error %1", xhr.status) : i18n("Network error")
                return
            }
            try {
                apply(JSON.parse(xhr.responseText))
                errorText = ""
            } catch (e) {
                errorText = i18n("Could not read response: %1", e.message)
            }
        }
        xhr.open("GET", apiUrl)
        xhr.send()
    }

    function apply(data) {
        const previous = indicator
        indicator = data.status.indicator
        summary = data.status.description
        // Skip group headers and the "Visit www.githubstatus.com…" placeholder.
        components = data.components.filter(c => !c.group && !c.name.startsWith("Visit "))
        incidents = data.incidents
        maintenances = data.scheduled_maintenances.filter(m => m.status === "in_progress")

        if (previous !== "unknown" && previous !== indicator && Plasmoid.configuration.notifyOnChange) {
            statusNotification.text = incidents.length > 0 ? incidents[0].name : summary
            statusNotification.title = i18n("GitHub: %1", summary)
            statusNotification.sendEvent()
        }
    }

    Plasmoid.icon: "vcs-branch"
    Plasmoid.status: indicator === "major" || indicator === "critical"
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("GitHub Status")
    toolTipSubText: errorText || summary

    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 12

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: i18n("Open githubstatus.com")
            icon.name: "internet-web-browser"
            onTriggered: Qt.openUrlExternally(root.pageUrl)
        }
    ]

    Notification {
        id: statusNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "vcs-branch"
    }

    Timer {
        interval: Plasmoid.configuration.pollInterval * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                root.expanded = !root.expanded
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: compact.containsMouse
        }

        Rectangle {
            width: Math.max(Kirigami.Units.smallSpacing * 2, parent.width * 0.35)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: root.errorText ? root.indicatorColor("unknown") : root.indicatorColor(root.indicator)
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: width
                    radius: width / 2
                    color: root.errorText ? root.indicatorColor("unknown") : root.indicatorColor(root.indicator)
                }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.summary
                    elide: Text.ElideRight
                }

                PlasmaComponents.ToolButton {
                    icon.name: "internet-web-browser"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Open githubstatus.com")
                    onClicked: Qt.openUrlExternally(root.pageUrl)
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    enabled: !root.loading
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
            text: root.errorText
                ? root.errorText
                : (isNaN(root.lastChecked) ? "" : i18n("Last checked %1", root.lastChecked.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)))
        }

        PlasmaComponents.ScrollView {
            id: scroll
            anchors.fill: parent

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                Kirigami.ListSectionHeader {
                    Layout.fillWidth: true
                    visible: incidentRepeater.count > 0
                    text: i18n("Active incidents")
                }

                Repeater {
                    id: incidentRepeater
                    model: root.incidents.concat(root.maintenances)

                    PlasmaComponents.ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        onClicked: Qt.openUrlExternally(modelData.shortlink)
                        contentItem: ColumnLayout {
                            spacing: 0
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: modelData.name
                                wrapMode: Text.WordWrap
                                font.bold: true
                                color: root.indicatorColor(modelData.impact === "none" ? "maintenance" : modelData.impact)
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: i18n("%1 · updated %2", modelData.status, root.formatTime(modelData.updated_at))
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }

                Kirigami.ListSectionHeader {
                    Layout.fillWidth: true
                    visible: componentRepeater.count > 0
                    text: i18n("Components")
                }

                Repeater {
                    id: componentRepeater
                    model: root.visibleComponents

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                            Layout.preferredHeight: width
                            radius: width / 2
                            color: root.componentColor(modelData.status)
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                        }
                        PlasmaComponents.Label {
                            text: root.componentLabel(modelData.status)
                            opacity: 0.7
                        }
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit * 2
                    visible: incidentRepeater.count === 0 && componentRepeater.count === 0
                    iconName: root.loading ? "view-refresh" : "checkmark"
                    text: root.loading ? i18n("Loading…") : i18n("All components operational")
                }
            }
        }
    }
}
