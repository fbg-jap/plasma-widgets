import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property string cfg_badgeStyle
    property string cfg_badgeStyleDefault
    property color cfg_colorFailed
    property color cfg_colorFailedDefault
    property color cfg_colorUnhealthy
    property color cfg_colorUnhealthyDefault
    property color cfg_colorRestarting
    property color cfg_colorRestartingDefault
    property color cfg_colorPaused
    property color cfg_colorPausedDefault
    property color cfg_colorStopped
    property color cfg_colorStoppedDefault
    property color cfg_colorRunning
    property color cfg_colorRunningDefault
    property color cfg_colorCountBackground
    property color cfg_colorCountBackgroundDefault

    // One row per colour setting: the config key (without "cfg_") and its label.
    readonly property var colorSettings: [
        { key: "colorFailed", label: i18n("Failed:") },
        { key: "colorUnhealthy", label: i18n("Unhealthy:") },
        { key: "colorRestarting", label: i18n("Restarting:") },
        { key: "colorPaused", label: i18n("Paused:") },
        { key: "colorStopped", label: i18n("Stopped:") },
        { key: "colorRunning", label: i18n("Running:") },
        { key: "colorCountBackground", label: i18n("Count background:") }
    ]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Badge style:")
            model: [i18n("Square"), i18n("Rounded")]
            currentIndex: page.cfg_badgeStyle === "rounded" ? 1 : 0
            onActivated: index => page.cfg_badgeStyle = index === 1 ? "rounded" : "square"
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Colours")
        }

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
