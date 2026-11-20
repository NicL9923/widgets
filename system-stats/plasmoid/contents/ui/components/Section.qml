import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// A titled popup section, like Stats' "Usage history" and "Details" blocks.
ColumnLayout {
    id: section

    property string title
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: section.title !== ""
        text: section.title
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.8
    }

    ColumnLayout {
        id: body

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2
    }
}
