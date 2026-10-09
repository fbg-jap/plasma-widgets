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
    // Which gh account to show; empty means gh's active account.
    readonly property string account: Plasmoid.configuration.account.trim()

    property string login: ""
    property var notifications: []
    property var reviews: []
    property var pullRequests: []
    property var repos: []
    // Totals from GitHub, not capped at the 20 items the lists show.
    property int prCount: 0
    property int reviewCount: 0
    property var seenNotificationIds: null
    property date lastChecked
    property string errorText: ""
    property bool loading: false

    readonly property var unreadNotifications: notifications.filter(n => n.unread)

    // CI state of your open PRs plus the main branch of your recently pushed repos.
    readonly property var ciStates: pullRequests.map(pr => pr.ci).concat(repos.map(r => r.ci))
    readonly property int ciFailing: ciStates.filter(st => st === "FAILURE" || st === "ERROR").length
    readonly property int ciRunning: ciStates.filter(st => st === "PENDING" || st === "EXPECTED").length
    readonly property int ciPassing: ciStates.filter(st => st === "SUCCESS").length

    // Badge and dot colours from the Appearance settings; they default to GitHub's own colours.
    readonly property color reviewsColor: Plasmoid.configuration.colorReviews
    readonly property color notificationsColor: Plasmoid.configuration.colorNotifications
    readonly property color pullRequestsColor: Plasmoid.configuration.colorPullRequests
    readonly property color ciFailingColor: Plasmoid.configuration.colorCiFailing
    readonly property color ciRunningColor: Plasmoid.configuration.colorCiRunning
    readonly property color ciPassingColor: Plasmoid.configuration.colorCiPassing

    // White or near-black, whichever reads better on the given background colour.
    function contrastText(background) {
        const c = Qt.color(background)
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.6 ? "#202020" : "white"
    }


    // The badges shown in the panel and the popup, PRTG-status-bar style; zero counts are hidden.
    readonly property var countBadges: [
        { label: i18n("review requests"), icon: "view-visible-symbolic", color: reviewsColor, count: reviewCount },
        { label: i18n("unread notifications"), icon: "notifications-symbolic", color: notificationsColor, count: unreadNotifications.length },
        { label: i18n("open pull requests"), icon: "vcs-merge-request-symbolic", color: pullRequestsColor, count: prCount },
        { label: i18n("CI failing"), icon: "dialog-cancel-symbolic", color: ciFailingColor, count: ciFailing },
        { label: i18n("CI running"), icon: "chronometer-symbolic", color: ciRunningColor, count: ciRunning },
        { label: i18n("CI passing"), icon: "checkmark-symbolic", color: ciPassingColor, count: ciPassing },
    ]
    readonly property var visibleBadges: countBadges.filter(b => b.count > 0)

    function ciColor(state) {
        switch (state) {
        case "SUCCESS": return ciPassingColor
        case "FAILURE":
        case "ERROR": return ciFailingColor
        case "PENDING":
        case "EXPECTED": return ciRunningColor
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

    function shellQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function refresh(markRead) {
        loading = true
        executable.exec("sh " + shellQuote(scriptPath) + " " + shellQuote(account) + (markRead ? " mark-read" : ""))
    }

    onAccountChanged: {
        login = ""
        notifications = []
        reviews = []
        pullRequests = []
        repos = []
        prCount = 0
        reviewCount = 0
        seenNotificationIds = null
        errorText = ""
        refresh(false)
    }

    function apply(data) {
        const gql = data.graphql.data
        login = gql.viewer.login
        notifications = data.notifications
        reviews = gql.reviews.nodes.filter(pr => pr.url)
        reviewCount = gql.reviews.issueCount
        prCount = gql.viewer.pullRequests.totalCount
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
            newNotification.text = fresh[0].repository.full_name + " · @" + login
        } else {
            newNotification.title = i18np("%1 new GitHub notification", "%1 new GitHub notifications", fresh.length)
            newNotification.text = fresh.map(n => n.subject.title).slice(0, 3).concat(["@" + login]).join("\n")
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
    Plasmoid.status: ciFailing > 0 || reviewCount > 0
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: login ? i18n("GitHub: %1", login) : i18n("GitHub Account")
    toolTipSubText: errorText
        || (login && visibleBadges.length === 0 ? i18n("Nothing needs your attention") : "")
        || visibleBadges.map(b => i18n("%1 %2", b.count, b.label)).join(" · ")

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

    // A PRTG-style count badge: an icon on a block of the badge's colour, then the count.
    component CountBadge: Rectangle {
        property var badge
        property real size
        readonly property bool rounded: Plasmoid.configuration.badgeStyle === "rounded"

        implicitHeight: size
        implicitWidth: iconBlock.width + countLabel.implicitWidth + size * (rounded ? 0.7 : 0.5)
        radius: rounded ? height / 2 : 2
        color: Plasmoid.configuration.colorCountBackground
        border.width: rounded ? 1.5 : 1
        border.color: badge.color

        Rectangle {
            id: iconBlock
            width: parent.size
            height: parent.size
            radius: parent.rounded ? width / 2 : 2
            color: badge.color

            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.height * 0.65
                height: width
                source: badge.icon
                isMask: true
                color: root.contrastText(badge.color)
            }
        }

        PlasmaComponents.Label {
            id: countLabel
            anchors.left: iconBlock.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: badge.count
            color: root.contrastText(Plasmoid.configuration.colorCountBackground)
            font.pixelSize: parent.size * 0.6
        }
    }

    // A row (or column, in a vertical panel) of count badges, one per non-zero count.
    component BadgeBar: GridLayout {
        id: bar
        property real badgeSize
        property bool vertical: false
        property bool showLogo: false
        readonly property int itemCount: root.visibleBadges.length + (showLogo ? 1 : 0)

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
            model: root.visibleBadges
            CountBadge {
                required property var modelData
                badge: modelData
                size: badgeSize
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real badgeSize: Math.min(Kirigami.Units.iconSizes.smallMedium, vertical ? width : height)
        readonly property bool showBadges: root.login !== "" && root.visibleBadges.length > 0

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh(false)
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
            showLogo: Plasmoid.configuration.showLogo
            vertical: compact.vertical
            badgeSize: compact.badgeSize
            opacity: root.errorText ? 0.5 : 1
        }

        // While loading, on errors, or when nothing needs attention.
        Kirigami.Icon {
            anchors.centerIn: parent
            width: compact.badgeSize
            height: compact.badgeSize
            visible: !compact.showBadges
            source: Plasmoid.icon
            active: compact.containsMouse
            opacity: root.errorText || root.login === "" ? 0.5 : 1
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

        footer: ColumnLayout {
            spacing: 0

            BadgeBar {
                Layout.margins: Kirigami.Units.smallSpacing
                Layout.bottomMargin: 0
                visible: root.login !== ""
                badgeSize: Kirigami.Units.iconSizes.small * 1.25
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
            visible: root.errorText !== "" && root.login === ""
            iconName: "dialog-error"
            text: i18n("Could not reach GitHub")
            explanation: i18n("%1\n\nMake sure the gh CLI is installed and logged in (gh auth login).", root.errorText)
        }

        PlasmaComponents.ScrollView {
            id: scroll
            anchors.fill: parent
            // Long titles are elided instead of making the list scroll sideways.
            contentWidth: availableWidth
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
                        dotColor: root.reviewsColor
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
