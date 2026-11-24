import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Stats' memory pressure gauge: three arcs, with the current band lit.
ColumnLayout {
    id: gauge

    property string level: "unknown"
    property int size: Kirigami.Units.gridUnit * 4

    readonly property var bands: [
        {level: "normal", color: Kirigami.Theme.positiveTextColor},
        {level: "warning", color: Kirigami.Theme.neutralTextColor},
        {level: "critical", color: Kirigami.Theme.negativeTextColor},
    ]

    spacing: Kirigami.Units.smallSpacing / 2

    Item {
        Layout.preferredWidth: gauge.size
        Layout.preferredHeight: gauge.size
        Layout.alignment: Qt.AlignHCenter

        Repeater {
            model: gauge.bands

            Shape {
                id: arc

                required property var modelData
                required property int index
                readonly property real stroke: Math.max(3, gauge.size * 0.09)

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: gauge.level === modelData.level ? 1 : 0.25

                ShapePath {
                    strokeColor: arc.modelData.color
                    strokeWidth: arc.stroke
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathAngleArc {
                        centerX: gauge.size / 2
                        centerY: gauge.size / 2
                        radiusX: (gauge.size - arc.stroke) / 2
                        radiusY: radiusX
                        startAngle: 135 + arc.index * 90 + 2
                        sweepAngle: 86
                    }
                }
            }
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: ({normal: i18n("Normal"), warning: i18n("Warning"), critical: i18n("Critical")})[gauge.level] || "–"
            font: Kirigami.Theme.smallFont
        }
    }

    PlasmaComponents.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18n("Memory pressure")
        font: Kirigami.Theme.smallFont
        opacity: 0.8
    }
}
