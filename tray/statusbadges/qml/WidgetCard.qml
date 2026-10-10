import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One configured widget in the popup: name, summary and badges, and its items when expanded.
Rectangle {
    id: card
    property var widget
    property bool expanded: widget.problemCount > 0
    readonly property color textColor: palette.windowText

    implicitHeight: column.implicitHeight + 16
    radius: 6
    color: Qt.rgba(palette.base.r, palette.base.g, palette.base.b, 0.9)
    border.color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            GlyphButton {
                glyph: card.expanded ? "chevronDown" : "chevronRight"
                tip: card.expanded ? "Hide details" : "Show details"
                size: 22
                onClicked: card.expanded = !card.expanded
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: card.widget.name
                    textFormat: Text.PlainText
                    font.bold: true
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.widget.summary + (card.widget.lastChecked ? "  ·  checked " + card.widget.lastChecked : "")
                    textFormat: Text.PlainText
                    opacity: 0.65
                    font.pointSize: Qt.application.font.pointSize * 0.85
                    elide: Text.ElideRight
                }
            }

            BusyIndicator {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                running: card.widget.loading
                visible: running
            }

            GlyphButton {
                glyph: "restart"
                tip: "Refresh"
                size: 22
                enabled: !card.widget.loading
                onClicked: controller.refresh(card.widget.wid)
            }
        }

        BadgeBar {
            Layout.fillWidth: true
            badges: card.widget.badges
            showTotal: card.widget.showTotal
            total: card.widget.total
            textColor: card.textColor
            visible: badges.length > 0 || showTotal
        }

        Label {
            Layout.fillWidth: true
            visible: card.widget.error !== ""
            text: card.widget.error
            textFormat: Text.PlainText
            color: "#d71920"
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: card.expanded
            spacing: 2

            Repeater {
                model: card.widget.sections

                ColumnLayout {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    // The title, and the section's own actions if any (e.g. a whole Compose stack).
                    RowLayout {
                        id: sectionHeader
                        readonly property bool busy: section.modelData.id !== ""
                            && card.widget.busyItems.indexOf(section.modelData.id) >= 0
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.rightMargin: 2
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            text: section.modelData.title
                            textFormat: Text.PlainText
                            font.bold: true
                            opacity: 0.75
                            elide: Text.ElideRight
                        }

                        BusyIndicator {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            running: sectionHeader.busy
                            visible: running
                        }

                        Repeater {
                            model: sectionHeader.busy ? [] : section.modelData.actions
                            GlyphButton {
                                required property var modelData
                                glyph: modelData.glyph
                                tip: modelData.label
                                onClicked: controller.runAction(card.widget.wid, section.modelData.id, modelData.id)
                            }
                        }
                    }

                    Repeater {
                        model: section.modelData.items

                        Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool busy: card.widget.busyItems.indexOf(modelData.id) >= 0
                                || sectionHeader.busy
                            Layout.fillWidth: true
                            implicitHeight: rowLayout.implicitHeight + 8
                            radius: 4
                            color: rowArea.containsMouse && modelData.url ? Qt.rgba(0.5, 0.5, 0.5, 0.15) : "transparent"

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: controller.openUrl(row.modelData.url)
                            }

                            RowLayout {
                                id: rowLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 4
                                anchors.rightMargin: 2
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 9
                                    Layout.preferredHeight: 9
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 5
                                    radius: 4.5
                                    color: card.widget.stateColors[row.modelData.state] || "transparent"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label {
                                        Layout.fillWidth: true
                                        text: row.modelData.title
                                        textFormat: Text.PlainText   // names and titles come from the services
                                        font.bold: row.modelData.bold
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: row.modelData.subtitle
                                        textFormat: Text.PlainText
                                        opacity: 0.65
                                        font.pointSize: Qt.application.font.pointSize * 0.85
                                        elide: Text.ElideRight
                                    }
                                }

                                BusyIndicator {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    running: row.busy
                                    visible: running
                                }

                                Repeater {
                                    model: row.busy ? [] : row.modelData.actions
                                    GlyphButton {
                                        required property var modelData
                                        glyph: modelData.glyph
                                        tip: modelData.label
                                        onClicked: controller.runAction(card.widget.wid, row.modelData.id, modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: card.widget.sections.length === 0 && !card.widget.error
                text: card.widget.loading ? "Loading…" : "Nothing to list."
                opacity: 0.65
            }
        }
    }
}
