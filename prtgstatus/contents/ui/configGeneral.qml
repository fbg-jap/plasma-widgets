import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_serverUrl: serverUrl.text
    property alias cfg_pollInterval: pollInterval.value
    property alias cfg_notifyOnDown: notifyOnDown.checked

    readonly property string normalizedUrl: serverUrl.text.trim().replace(/\/+$/, "")

    Kirigami.FormLayout {
        QQC2.TextField {
            id: serverUrl
            Kirigami.FormData.label: i18n("PRTG server:")
            Layout.fillWidth: true
            placeholderText: "https://prtg.example.com"
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("API key:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Create a read-only API key in PRTG (Setup → Account Settings → API Keys), then store it in your keyring by running this in a terminal. Paste the key at the \"Password:\" prompt, not into the command:")
            }
            Kirigami.SelectableLabel {
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                font.family: "monospace"
                text: "secret-tool store --label=\"PRTG API key\" service plasma-prtg server "
                    + (normalizedUrl || "https://prtg.example.com")
            }
        }

        QQC2.SpinBox {
            id: pollInterval
            Kirigami.FormData.label: i18n("Check every:")
            from: 1
            to: 60
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text)
        }

        QQC2.CheckBox {
            id: notifyOnDown
            text: i18n("Notify when a sensor goes down")
        }
    }
}
