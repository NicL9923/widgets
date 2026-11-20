import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A horizontal bar split into colored segments: [{fraction, color}].
Rectangle {
    id: bar

    property var segments: []

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.smallSpacing * 2
    radius: height / 2
    color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    clip: true

    Row {
        anchors.fill: parent

        Repeater {
            model: bar.segments

            Rectangle {
                required property var modelData
                width: bar.width * Math.max(0, Math.min(1, modelData.fraction))
                height: bar.height
                color: modelData.color
            }
        }
    }
}
