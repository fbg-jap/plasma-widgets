import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property color cfg_colorReviews
    property color cfg_colorReviewsDefault
    property color cfg_colorNotifications
    property color cfg_colorNotificationsDefault
    property color cfg_colorPullRequests
    property color cfg_colorPullRequestsDefault
    property color cfg_colorCiFailing
    property color cfg_colorCiFailingDefault
    property color cfg_colorCiRunning
    property color cfg_colorCiRunningDefault
    property color cfg_colorCiPassing
    property color cfg_colorCiPassingDefault
    property color cfg_colorCountBackground
    property color cfg_colorCountBackgroundDefault

    // One row per colour setting: the config key (without "cfg_") and its label.
    readonly property var colorSettings: [
        { key: "colorReviews", label: i18n("Review requests:") },
        { key: "colorNotifications", label: i18n("Unread notifications:") },
        { key: "colorPullRequests", label: i18n("Open pull requests:") },
        { key: "colorCiFailing", label: i18n("CI failing:") },
        { key: "colorCiRunning", label: i18n("CI running:") },
        { key: "colorCiPassing", label: i18n("CI passing:") },
        { key: "colorCountBackground", label: i18n("Count background:") }
    ]

    Kirigami.FormLayout {
        Repeater {
            model: page.colorSettings

            RowLayout {
                required property var modelData
                readonly property string key: "cfg_" + modelData.key
                readonly property bool isDefault: Qt.colorEqual(page[key], page[key + "Default"])

                Kirigami.FormData.label: modelData.label

                KQuickControls.ColorButton {
                    color: page[key]
                    dialogTitle: modelData.label
                    showAlphaChannel: false
                    onAccepted: picked => page[key] = picked
                }

                QQC2.ToolButton {
                    icon.name: "edit-reset"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Reset to default")
                    enabled: !isDefault
                    onClicked: page[key] = page[key + "Default"]
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("The symbol and number on each badge switch between white and dark text to stay readable on the colour you pick.")
        }
    }
}
