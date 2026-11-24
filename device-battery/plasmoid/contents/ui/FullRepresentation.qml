import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import "BatteryState.js" as BatteryState

PlasmaExtras.Representation {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 6
    Layout.preferredHeight: content.implicitHeight + full.header.height + Kirigami.Units.largeSpacing * 2

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 2
                text: i18n("Device battery")
                elide: Text.ElideRight
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Refresh now")
                enabled: !root.busy
                onClicked: root.poll()
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    ColumnLayout {
        id: content

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: root.devices

            ColumnLayout {
                id: row

                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: BatteryState.kindIcon(row.modelData.kind)
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        elide: Text.ElideRight
                    }

                    PlasmaComponents.Label {
                        visible: text !== ""
                        text: root.stateText(row.modelData)
                        color: row.modelData.asleep ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.positiveTextColor
                        font: Kirigami.Theme.smallFont
                    }

                    PlasmaComponents.Label {
                        text: BatteryState.percentText(row.modelData)
                        font.features: { "tnum": 1 }
                        font.weight: Font.DemiBold
                        color: root.levelColor(row.modelData)
                    }
                }

                PlasmaComponents.ProgressBar {
                    Layout.fillWidth: true
                    opacity: row.modelData.asleep ? 0.5 : 1
                    visible: !(row.modelData.asleep && row.modelData.percent === null)
                    from: 0
                    to: 100
                    value: row.modelData.percent === null ? 0 : row.modelData.percent
                    indeterminate: row.modelData.percent === null && row.modelData.charging
                    Accessible.name: i18n("%1 battery", row.modelData.name)
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignCenter
            visible: root.loaded && root.devices.length === 0
            iconName: "battery-missing"
            text: i18n("No connected devices report a battery")
            explanation: i18n("Turn on a wireless headset, mouse, or Bluetooth device to see it here.")
        }

        Repeater {
            model: root.helperError !== "" ? [root.helperError].concat(root.errors) : root.errors

            RowLayout {
                required property string modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: "dialog-warning"
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: modelData
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                }
            }
        }
    }
}
