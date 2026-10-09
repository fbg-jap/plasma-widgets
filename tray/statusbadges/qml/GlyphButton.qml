import QtQuick
import QtQuick.Controls

// A small flat button showing one Glyph, with a tooltip.
Rectangle {
    id: button
    property string glyph
    property string tip
    property color glyphColor: palette.buttonText
    property real size: 26
    signal clicked()

    width: size
    height: size
    radius: 4
    color: area.pressed ? Qt.rgba(0.5, 0.5, 0.5, 0.35) : area.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.2) : "transparent"
    opacity: enabled ? 1 : 0.4

    Glyph {
        anchors.centerIn: parent
        width: parent.width * 0.62
        height: width
        kind: button.glyph
        color: button.glyphColor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    ToolTip.visible: area.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
