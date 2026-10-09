import QtQuick

// A wrapping row of badges, optionally followed by the total, e.g. "(of 919)".
Flow {
    id: bar
    property var badges: []
    property real size: 22
    property bool showTotal: false
    property int total: 0
    property color textColor: "black"
    spacing: 5

    Repeater {
        model: bar.badges
        Badge {
            required property var modelData
            badgeState: modelData
            size: bar.size
        }
    }

    Text {
        visible: bar.showTotal
        height: bar.size
        verticalAlignment: Text.AlignVCenter
        text: "(of " + bar.total + ")"
        color: bar.textColor
        font.pixelSize: bar.size * 0.6
    }
}
