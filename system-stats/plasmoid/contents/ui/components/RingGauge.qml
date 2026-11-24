import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// A 270-degree gauge with the value in the middle and a caption below.
ColumnLayout {
    id: gauge

    property real fraction: 0
    property bool known: true
    property string valueText
    property string caption
    property color color: Kirigami.Theme.highlightColor
    property int size: Kirigami.Units.gridUnit * 4

    spacing: Kirigami.Units.smallSpacing / 2

    Item {
        Layout.preferredWidth: gauge.size
        Layout.preferredHeight: gauge.size
        Layout.alignment: Qt.AlignHCenter

        Shape {
            id: shape

            readonly property real stroke: Math.max(3, gauge.size * 0.09)
            readonly property real radius: (gauge.size - stroke) / 2

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                strokeWidth: shape.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gauge.size / 2
                    centerY: gauge.size / 2
                    radiusX: shape.radius
                    radiusY: shape.radius
                    startAngle: 135
                    sweepAngle: 270
                }
            }

            ShapePath {
                strokeColor: gauge.known && gauge.fraction > 0 ? gauge.color : "transparent"
                strokeWidth: shape.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gauge.size / 2
                    centerY: gauge.size / 2
                    radiusX: shape.radius
                    radiusY: shape.radius
                    startAngle: 135
                    sweepAngle: 270 * Math.max(0, Math.min(1, gauge.fraction))
                }
            }
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: gauge.known ? gauge.valueText : "–"
            font.pixelSize: Math.round(gauge.size * 0.22)
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    PlasmaComponents.Label {
        Layout.alignment: Qt.AlignHCenter
        visible: gauge.caption !== ""
        text: gauge.caption
        font: Kirigami.Theme.smallFont
        opacity: 0.8
    }
}
