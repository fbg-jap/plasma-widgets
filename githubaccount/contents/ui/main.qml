import QtQuick
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

    property string login: ""
    property var notifications: []
    property var reviews: []
    property var pullRequests: []
    property var repos: []
    property var seenNotificationIds: null
    property date lastChecked
    property string errorText: ""
    property bool loading: false

    readonly property var unreadNotifications: notifications.filter(n => n.unread)
    readonly property int badgeCount: unreadNotifications.length + reviews.length

    function ciColor(state) {
        switch (state) {
        case "SUCCESS": return Kirigami.Theme.positiveTextColor
        case "FAILURE":
        case "ERROR": return Kirigami.Theme.negativeTextColor
        case "PENDING":
        case "EXPECTED": return Kirigami.Theme.neutralTextColor
        default: return Kirigami.Theme.disabledTextColor
        }
    }

    function ciLabel(state) {
        switch (state) {
        case "SUCCESS": return i18n("Checks passed")
        case "FAILURE":
        case "ERROR": return i18n("Checks failed")
        case "PENDING":
        case "EXPECTED": return i18n("Checks running")
        default: return i18n("No checks")
        }
    }

    function notificationUrl(n) {
        if (n.subject.type === "Release") {
            return n.repository.html_url + "/releases"
        }
        if (!n.subject.url) {
            return "https://github.com/notifications"
        }
        return n.subject.url
            .replace("https://api.github.com/repos/", "https://github.com/")
            .replace("/pulls/", "/pull/")
            .replace("/commits/", "/commit/")
    }

    function relativeTime(iso) {
        const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
        if (minutes < 60) return i18np("%1 minute ago", "%1 minutes ago", Math.max(minutes, 1))
        const hours = Math.round(minutes / 60)
        if (hours < 24) return i18np("%1 hour ago", "%1 hours ago", hours)
        return i18np("%1 day ago", "%1 days ago", Math.round(hours / 24))
    }

    function refresh(markRead) {
        loading = true
        executable.exec("sh '" + scriptPath + "'" + (markRead ? " mark-read" : ""))
    }

    function apply(data) {
        const gql = data.graphql.data
        login = gql.viewer.login
        notifications = data.notifications
        reviews = gql.reviews.nodes.filter(pr => pr.url)
        pullRequests = gql.viewer.pullRequests.nodes.map(pr => ({
            title: pr.title,
            url: pr.url,
            number: pr.number,
            isDraft: pr.isDraft,
            repo: pr.repository.nameWithOwner,
            ci: pr.commits.nodes.length && pr.commits.nodes[0].commit.statusCheckRollup
                ? pr.commits.nodes[0].commit.statusCheckRollup.state : null
        }))
        repos = gql.viewer.repositories.nodes.map(r => ({
            name: r.nameWithOwner,
            url: r.url,
            pushedAt: r.pushedAt,
            ci: r.defaultBranchRef && r.defaultBranchRef.target.statusCheckRollup
                ? r.defaultBranchRef.target.statusCheckRollup.state : null
        }))
        notifyAboutNew()
    }

    function notifyAboutNew() {
        const fresh = unreadNotifications.filter(n => seenNotificationIds && !seenNotificationIds[n.id])
        const seen = {}
        notifications.forEach(n => seen[n.id] = true)
        seenNotificationIds = seen

        if (fresh.length === 0 || !Plasmoid.configuration.notifyOnNew) {
            return
        }
        if (fresh.length === 1) {
            newNotification.title = fresh[0].subject.title
            newNotification.text = fresh[0].repository.full_name
        } else {
            newNotification.title = i18np("%1 new GitHub notification", "%1 new GitHub notifications", fresh.length)
            newNotification.text = fresh.map(n => n.subject.title).slice(0, 3).join("\n")
        }
        newNotification.sendEvent()
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
                root.errorText = stderr || i18n("gh exited with code %1", data["exit code"])
                return
            }
            try {
                root.apply(JSON.parse(data["stdout"]))
                root.errorText = ""
            } catch (e) {
                root.errorText = i18n("Could not read gh output: %1", e.message)
            }
        }
    }

    Plasmoid.icon: "vcs-branch"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    toolTipMainText: login ? i18n("GitHub: %1", login) : i18n("GitHub Account")
    toolTipSubText: errorText
        || i18n("%1 unread notifications · %2 review requests", unreadNotifications.length, reviews.length)

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh(false)
        },
        PlasmaCore.Action {
            text: i18n("Mark All Notifications Read")
            icon.name: "mail-mark-read"
            enabled: root.unreadNotifications.length > 0
            onTriggered: root.refresh(true)
        },
        PlasmaCore.Action {
            text: i18n("Open GitHub Notifications")
            icon.name: "internet-web-browser"
            onTriggered: Qt.openUrlExternally("https://github.com/notifications")
        }
    ]

    Notification {
        id: newNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "vcs-branch"
    }

    Timer {
        interval: Plasmoid.configuration.pollInterval * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh(false)
            } else {
                root.expanded = !root.expanded
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: compact.containsMouse
            opacity: root.errorText ? 0.5 : 1
        }

        Rectangle {
            visible: root.badgeCount > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(Kirigami.Units.gridUnit * 0.75, parent.height * 0.5)
            width: Math.max(height, badgeLabel.implicitWidth + Kirigami.Units.smallSpacing)
            radius: height / 2
            color: Kirigami.Theme.highlightColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor

            PlasmaComponents.Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.badgeCount > 99 ? "99+" : root.badgeCount
                color: Kirigami.Theme.highlightedTextColor
                font.pixelSize: parent.height * 0.75
                font.bold: true
            }
        }
    }

    // One clickable line in the popup: optional status dot, title and a dimmed subtitle.
    component EntryRow: PlasmaComponents.ItemDelegate {
        property string title
        property string subtitle
        property string url
        property color dotColor: "transparent"
        property bool bold: false

        Layout.fillWidth: true
        onClicked: Qt.openUrlExternally(url)

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
                    text: title
                    font.bold: bold
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: subtitle
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideRight
                }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.login ? "@" + root.login : i18n("GitHub Account")
                    elide: Text.ElideRight
                }

                PlasmaComponents.ToolButton {
                    icon.name: "mail-mark-read"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Mark all notifications read")
                    enabled: !root.loading && root.unreadNotifications.length > 0
                    onClicked: root.refresh(true)
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }

                PlasmaComponents.ToolButton {
                    icon.name: "internet-web-browser"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Open GitHub notifications")
                    onClicked: Qt.openUrlExternally("https://github.com/notifications")
                    PlasmaComponents.ToolTip.text: text
                    PlasmaComponents.ToolTip.visible: hovered
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    enabled: !root.loading
                    onClicked: root.refresh(false)
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
            visible: root.errorText !== "" && root.login === ""
            iconName: "dialog-error"
            text: i18n("Could not reach GitHub")
            explanation: i18n("%1\n\nMake sure the gh CLI is installed and logged in (gh auth login).", root.errorText)
        }

        PlasmaComponents.ScrollView {
            id: scroll
            anchors.fill: parent
            visible: root.login !== ""

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

                Kirigami.ListSectionHeader {
                    Layout.fillWidth: true
                    visible: root.reviews.length > 0
                    text: i18n("Review requested (%1)", root.reviews.length)
                }
                Repeater {
                    model: root.reviews
                    EntryRow {
                        required property var modelData
                        title: modelData.title
                        subtitle: i18n("%1 #%2 by %3", modelData.repository.nameWithOwner, modelData.number,
                                       modelData.author ? modelData.author.login : i18n("unknown"))
                        url: modelData.url
                        dotColor: Kirigami.Theme.highlightColor
                        bold: true
                    }
                }

                Kirigami.ListSectionHeader {
                    Layout.fillWidth: true
                    text: i18n("Notifications (%1 unread)", root.unreadNotifications.length)
                }
                Repeater {
                    model: root.notifications
                    EntryRow {
                        required property var modelData
                        title: modelData.subject.title
                        subtitle: i18n("%1 · %2 · %3", modelData.repository.full_name,
                                       modelData.reason.replace(/_/g, " "), root.relativeTime(modelData.updated_at))
                        url: root.notificationUrl(modelData)
                        dotColor: modelData.unread ? Kirigami.Theme.highlightColor : "transparent"
                        bold: modelData.unread
                    }
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.largeSpacing
                    visible: root.notifications.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.7
                    text: i18n("You're all caught up")
                }

                Kirigami.ListSectionHeader {
                    Layout.fillWidth: true
                    visible: root.pullRequests.length > 0
                    text: i18n("Your open pull requests (%1)", root.pullRequests.length)
                }
                Repeater {
                    model: root.pullRequests
                    EntryRow {
                        required property var modelData
                        title: (modelData.isDraft ? i18n("[Draft] ") : "") + modelData.title
                        subtitle: i18n("%1 #%2 · %3", modelData.repo, modelData.number, root.ciLabel(modelData.ci))
                        url: modelData.url
                        dotColor: root.ciColor(modelData.ci)
                    }
                }

                Kirigami.ListSectionHeader {
                    Layout.fillWidth: true
                    visible: Plasmoid.configuration.showRepos && root.repos.length > 0
                    text: i18n("Recently pushed repositories")
                }
                Repeater {
                    model: Plasmoid.configuration.showRepos ? root.repos : []
                    EntryRow {
                        required property var modelData
                        title: modelData.name
                        subtitle: i18n("%1 · pushed %2", root.ciLabel(modelData.ci), root.relativeTime(modelData.pushedAt))
                        url: modelData.url + "/actions"
                        dotColor: root.ciColor(modelData.ci)
                    }
                }
            }
        }
    }
}
