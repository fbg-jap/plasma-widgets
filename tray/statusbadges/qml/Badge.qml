import QtQuick
import QtQuick.Controls

// A status badge in the style of PRTG's status bar: the state's symbol on a block of its
// colour, then the count. Square or rounded (pill-shaped), as chosen in the settings.
Rectangle {
    id: badge
    property var badgeState      // {key, label, glyph, color, count}
    property real size: 22
    property bool rounded: controller.badgeStyle === "rounded"

    function contrastText(background) {
        const c = Qt.color(background)
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.6 ? "#202020" : "white"
    }

    implicitHeight: size
    implicitWidth: block.width + countLabel.implicitWidth + size * (rounded ? 0.7 : 0.5)
    radius: rounded ? height / 2 : 2
    color: "#2b2f33"
    border.width: rounded ? 1.5 : 1
    border.color: badgeState.color

    Rectangle {
        id: block
        width: badge.size
        height: badge.size
        radius: badge.rounded ? width / 2 : 2
        color: badge.badgeState.color

        Glyph {
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: width
            kind: badge.badgeState.glyph
            color: badge.contrastText(badge.badgeState.color)
        }
    }

    Text {
        id: countLabel
        anchors.left: block.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: badge.badgeState.count
        color: "white"
        font.pixelSize: badge.size * 0.6
    }

    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: badge.badgeState.count + " " + badge.badgeState.label.toLowerCase()
    ToolTip.delay: 400
}
