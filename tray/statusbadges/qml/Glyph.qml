import QtQuick
import QtQuick.Shapes

// A badge or button symbol as vector paths on a 100×100 grid: exactly centred and sharp at any
// size. "stroke" paths are drawn as rounded lines, "fill" paths are filled.
Item {
    id: glyph
    property string kind
    property color color: "white"

    readonly property var paths: ({
        check: { stroke: "M 25 52 L 43 70 L 76 32" },
        cross: { stroke: "M 30 30 L 70 70 M 70 30 L 30 70" },
        exclamation: { stroke: "M 50 22 L 50 54", fill: "M 42 72 A 8 8 0 1 0 58 72 A 8 8 0 1 0 42 72 Z" },
        wave: { stroke: "M 20 55 C 30 30, 42 30, 50 50 C 58 70, 70 70, 80 45" },
        dash: { stroke: "M 24 50 L 40 50 M 60 50 L 76 50" },
        question: { stroke: "M 37 37 C 37 21, 63 21, 63 37 C 63 49, 50 48, 50 58", fill: "M 43 74 A 7 7 0 1 0 57 74 A 7 7 0 1 0 43 74 Z" },
        pause: { fill: "M 30 26 L 44 26 L 44 74 L 30 74 Z M 56 26 L 70 26 L 70 74 L 56 74 Z" },
        stop: { fill: "M 31 31 L 69 31 L 69 69 L 31 69 Z" },
        play: { fill: "M 36 25 L 76 50 L 36 75 Z" },
        restart: { stroke: "M 71 40 A 23 23 0 1 0 73 58", fill: "M 60 26 L 82 28 L 74 48 Z" },
        gear: { stroke: "M 50 34 A 16 16 0 1 1 49.9 34 M 50 14 L 50 24 M 50 76 L 50 86 M 14 50 L 24 50 M 76 50 L 86 50 M 25 25 L 32 32 M 68 68 L 75 75 M 75 25 L 68 32 M 25 75 L 32 68" },
        plus: { stroke: "M 50 26 L 50 74 M 26 50 L 74 50" },
        muted: { fill: "M 18 40 L 32 40 L 50 24 L 50 76 L 32 60 L 18 60 Z", stroke: "M 62 40 L 80 60 M 80 40 L 62 60" },
        eye: { stroke: "M 14 50 C 30 26, 70 26, 86 50 C 70 74, 30 74, 14 50 Z", fill: "M 40 50 A 10 10 0 1 0 60 50 A 10 10 0 1 0 40 50 Z" },
        bell: { fill: "M 50 18 C 37 18 30 29 30 42 L 30 60 L 22 70 L 78 70 L 70 60 L 70 42 C 70 29 63 18 50 18 Z M 42 76 A 8 8 0 0 0 58 76 Z" },
        merge: { stroke: "M 30 36 L 30 64 M 70 64 L 70 48 C 70 38 64 32 54 32 L 44 32",
                 fill: "M 19 25 A 11 11 0 1 0 41 25 A 11 11 0 1 0 19 25 Z M 19 75 A 11 11 0 1 0 41 75 A 11 11 0 1 0 19 75 Z M 59 75 A 11 11 0 1 0 81 75 A 11 11 0 1 0 59 75 Z" },
        upload: { stroke: "M 50 68 L 50 26 M 32 44 L 50 26 L 68 44 M 26 78 L 74 78" },
        external: { stroke: "M 44 26 L 26 26 L 26 74 L 74 74 L 74 56 M 56 26 L 74 26 L 74 44 M 74 26 L 46 54" },
        chevronDown: { stroke: "M 28 40 L 50 62 L 72 40" },
        chevronRight: { stroke: "M 40 28 L 62 50 L 40 72" },
        up: { stroke: "M 28 60 L 50 38 L 72 60" },
        down: { stroke: "M 28 40 L 50 62 L 72 40" },
        trash: { stroke: "M 24 30 L 76 30 M 42 30 L 42 22 L 58 22 L 58 30 M 32 30 L 36 78 L 64 78 L 68 30 M 45 42 L 45 66 M 55 42 L 55 66" },
    })
    readonly property var current: paths[kind] || ({})

    Shape {
        width: 100
        height: 100
        scale: glyph.width / 100
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: glyph.current.stroke ? glyph.color : "transparent"
            strokeWidth: 12
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: glyph.current.stroke || "M 0 0" }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: glyph.current.fill ? glyph.color : "transparent"
            PathSvg { path: glyph.current.fill || "M 0 0" }
        }
    }
}
