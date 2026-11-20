import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: row

    property string label
    property string value
    // Transparent hides the legend dot.
    property color dotColor: "transparent"
    property color valueColor: Kirigami.Theme.textColor

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Rectangle {
        visible: row.dotColor.a > 0
        Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
        Layout.preferredHeight: Layout.preferredWidth
        radius: width / 2
        color: row.dotColor
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: row.label
        elide: Text.ElideRight
        opacity: 0.8
    }

    PlasmaComponents.Label {
        text: row.value
        color: row.valueColor
        font.features: { "tnum": 1 }
    }
}
