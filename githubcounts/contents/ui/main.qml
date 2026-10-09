import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string scriptPath: Qt.resolvedUrl("../code/fetch.sh").toString().replace("file://", "")
    // Which gh account to show; empty means gh's active account.
    readonly property string account: Plasmoid.configuration.account.trim()

    property string login: ""
    property int prCount: -1
    property int reviewCount: -1
    // Things whose latest checks failed or are still running: your open PRs and the
    // default branch of your recently pushed repos. Each entry is {name, url}.
    property var ciFailing: []
    property var ciRunning: []
    property string errorText: ""

    readonly property bool loaded: prCount >= 0

    function shellQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function refresh() {
        executable.exec("sh " + shellQuote(scriptPath) + " " + shellQuote(account))
    }

    onAccountChanged: {
        login = ""
        prCount = -1
        reviewCount = -1
        ciFailing = []
        ciRunning = []
        errorText = ""
        refresh()
    }

    function apply(data) {
        const failing = []
        const running = []
        const track = (state, name, url) => {
            if (state === "FAILURE" || state === "ERROR") {
                failing.push({ name: name, url: url })
            } else if (state === "PENDING" || state === "EXPECTED") {
                running.push({ name: name, url: url })
            }
        }

        data.prs.nodes.forEach(pr => {
            const rollup = pr.commits.nodes.length ? pr.commits.nodes[0].commit.statusCheckRollup : null
            track(rollup ? rollup.state : null, pr.title, pr.url)
        })
        data.viewer.repositories.nodes.forEach(repo => {
            const rollup = repo.defaultBranchRef ? repo.defaultBranchRef.target.statusCheckRollup : null
            track(rollup ? rollup.state : null, repo.nameWithOwner, repo.url + "/actions")
        })

        login = data.viewer.login
        prCount = data.prs.issueCount
        reviewCount = data.reviews.issueCount
        ciFailing = failing
        ciRunning = running
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
            if (data["exit code"] !== 0) {
                root.errorText = data["stderr"].trim() || i18n("gh exited with code %1", data["exit code"])
                return
            }
            try {
                root.apply(JSON.parse(data["stdout"]).data)
                root.errorText = ""
            } catch (e) {
                root.errorText = i18n("Could not read gh output: %1", e.message)
            }
        }
    }

    Plasmoid.icon: "vcs-merge-request"
    Plasmoid.status: ciFailing.length > 0 || reviewCount > 0
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: login ? i18n("GitHub: %1", login) : i18n("GitHub Counts")
    toolTipTextFormat: Text.StyledText
    toolTipSubText: {
        if (errorText) {
            return errorText + "<br>" + i18n("Is the gh CLI logged in? (gh auth login)")
        }
        if (!loaded) {
            return i18n("Loading…")
        }
        let lines = [
            i18np("%1 open pull request", "%1 open pull requests", prCount),
            i18np("%1 review requested", "%1 reviews requested", reviewCount),
        ]
        if (ciFailing.length > 0) {
            lines.push("<b>" + i18n("CI failing:") + "</b> " + ciFailing.map(c => c.name).join(", "))
        }
        if (ciRunning.length > 0) {
            lines.push(i18n("CI running:") + " " + ciRunning.map(c => c.name).join(", "))
        }
        if (ciFailing.length === 0 && ciRunning.length === 0) {
            lines.push(i18n("CI: all passing"))
        }
        return lines.join("<br>")
    }

    preferredRepresentation: fullRepresentation

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    Timer {
        interval: Plasmoid.configuration.pollInterval * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // One icon + number pair; clicking it opens the matching GitHub page.
    component Counter: MouseArea {
        id: counter

        property string iconName
        property string value
        property color valueColor: Kirigami.Theme.textColor
        property string url

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real iconSize: Plasmoid.formFactor === PlasmaCore.Types.Planar
            ? Kirigami.Units.iconSizes.medium
            : Math.min(Kirigami.Units.iconSizes.smallMedium, root.height)

        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                Qt.openUrlExternally(url)
            }
        }

        Layout.fillHeight: !vertical
        Layout.fillWidth: vertical
        Layout.preferredWidth: row.implicitWidth
        Layout.preferredHeight: row.implicitHeight

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: counter.iconSize
                Layout.preferredHeight: counter.iconSize
                source: counter.iconName
                active: counter.containsMouse
            }
            PlasmaComponents.Label {
                text: counter.value
                color: counter.valueColor
                font.bold: true
                font.pixelSize: counter.iconSize * 0.75
            }
        }
    }

    fullRepresentation: GridLayout {
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: vertical ? 3 : 1
        columns: vertical ? 1 : 3
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing
        opacity: root.errorText ? 0.5 : 1

        Layout.minimumWidth: vertical ? 0 : implicitWidth
        Layout.minimumHeight: vertical ? implicitHeight : 0

        Counter {
            iconName: "vcs-merge-request"
            value: root.loaded ? root.prCount : "–"
            url: "https://github.com/pulls"
        }

        Counter {
            iconName: "view-visible"
            value: root.loaded ? root.reviewCount : "–"
            valueColor: root.reviewCount > 0 ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            url: "https://github.com/pulls/review-requested"
        }

        Counter {
            iconName: "run-build"
            // Show the number of failing items; fall back to running ones; ✓ when all is green.
            value: !root.loaded ? "–"
                : root.ciFailing.length > 0 ? root.ciFailing.length
                : root.ciRunning.length > 0 ? root.ciRunning.length
                : "✓"
            valueColor: root.ciFailing.length > 0 ? Kirigami.Theme.negativeTextColor
                : root.ciRunning.length > 0 ? Kirigami.Theme.neutralTextColor
                : Kirigami.Theme.positiveTextColor
            url: root.ciFailing.length > 0 ? root.ciFailing[0].url
                : root.ciRunning.length > 0 ? root.ciRunning[0].url
                : "https://github.com/pulls"
        }
    }
}
