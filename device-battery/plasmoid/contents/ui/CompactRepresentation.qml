import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "BatteryState.js" as BatteryState

MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int thickness: vertical ? width : height
    readonly property int iconSize: Math.max(Kirigami.Units.iconSizes.small,
        Math.min(Kirigami.Units.iconSizes.medium, Math.round(thickness * 0.5)))
    // With nothing connected the applet shrinks to nothing, except while the panel is being
    // edited, where it needs a handle to be moved or configured.
    readonly property bool placeholder: root.devices.length === 0
        && (root.editing || root.helperError !== "" || !root.loaded)

    Layout.minimumWidth: vertical ? 0 : (placeholder ? iconSize : layout.implicitWidth)
    Layout.minimumHeight: vertical ? (placeholder ? iconSize : layout.implicitHeight) : 0
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumWidth: vertical ? Infinity : Layout.minimumWidth

    activeFocusOnTab: true
    hoverEnabled: true
    Accessible.role: Accessible.Button
    Accessible.name: i18n("Device battery")
    Accessible.description: root.toolTipSubText
    onClicked: root.expanded = !root.expanded
    Keys.onReturnPressed: root.expanded = !root.expanded
    Keys.onSpacePressed: root.expanded = !root.expanded

    Kirigami.Icon {
        anchors.centerIn: parent
        width: compact.iconSize
        height: width
        visible: compact.placeholder
        source: root.helperError !== "" ? "dialog-warning" : "battery-070"
        opacity: root.loaded ? 1 : 0.5
    }

    GridLayout {
        id: layout

        anchors.centerIn: parent
        rows: compact.vertical ? root.devices.length : 1
        columns: compact.vertical ? 1 : root.devices.length
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.largeSpacing

        Repeater {
            model: root.devices

            // One icon-and-percentage pair per device, like Stats' Bluetooth stack.
            GridLayout {
                id: entry

                required property var modelData

                // A sleeping device keeps its place, faded, with its last real reading.
                opacity: modelData.asleep ? 0.5 : 1
                rows: compact.vertical ? 2 : 1
                columns: compact.vertical ? 1 : 2
                rowSpacing: 0
                columnSpacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.preferredWidth: compact.iconSize
                    Layout.preferredHeight: compact.iconSize
                    Layout.alignment: Qt.AlignCenter

                    Kirigami.Icon {
                        anchors.fill: parent
                        source: BatteryState.kindIcon(entry.modelData.kind)
                        color: root.levelColor(entry.modelData)
                        isMask: BatteryState.level(entry.modelData, root.lowThreshold) !== "normal"
                    }

                    Kirigami.Icon {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: -Kirigami.Units.smallSpacing / 2
                        width: Math.round(parent.width * 0.55)
                        height: width
                        visible: entry.modelData.charging
                        source: "battery-charging-symbolic"
                        color: Kirigami.Theme.positiveTextColor
                        isMask: true
                    }
                }

                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignCenter
                    visible: text !== ""
                    text: (Plasmoid.configuration.showNames && !compact.vertical
                        ? entry.modelData.name + " " : "") + BatteryState.percentText(entry.modelData)
                    font.features: { "tnum": 1 }
                    color: root.levelColor(entry.modelData)
                    fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                    minimumPixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }
    }
}
