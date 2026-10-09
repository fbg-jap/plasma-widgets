import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The popup shown when the tray icon is clicked: one card per configured widget.
Window {
    id: popup
    property bool standalone: false   // true when there's no system tray: behave as a normal window
    property alias settingsWindow: settingsWin

    SystemPalette { id: sys; colorGroup: SystemPalette.Active }

    title: "Status Badges"
    width: 460
    height: Math.min(Math.max(list.implicitHeight + header.implicitHeight + 34, 180), 720)
    flags: standalone ? Qt.Window : (Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
    color: sys.window
    onActiveChanged: if (!active && !standalone) hide()

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Qt.rgba(sys.windowText.r, sys.windowText.g, sys.windowText.b, 0.25)
        visible: !popup.standalone
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            id: header
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: "Status Badges"
                font.bold: true
                font.pointSize: Qt.application.font.pointSize * 1.15
            }
            GlyphButton {
                glyph: "restart"
                tip: "Refresh all"
                onClicked: controller.refreshAll()
            }
            GlyphButton {
                glyph: "gear"
                tip: "Settings"
                onClicked: {
                    if (!popup.standalone) popup.hide()
                    controller.openSettings()
                }
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            visible: controller.widgets.length > 0

            ColumnLayout {
                id: list
                width: scroll.availableWidth
                spacing: 8

                Repeater {
                    model: controller.widgets
                    WidgetCard {
                        required property var modelData
                        Layout.fillWidth: true
                        widget: modelData
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: controller.widgets.length === 0
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "No widgets yet. Add GitHub, PRTG, Docker, Bugsink or Dokploy in the settings."
            }
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Add widgets…"
                onClicked: controller.openSettings()
            }
        }
    }

    SettingsWindow { id: settingsWin; objectName: "settingsWindow" }
}
