import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

PlasmaExtras.Representation {
    id: full

    // Stats' popups are 264 points wide.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 17
    Layout.minimumHeight: Kirigami.Units.gridUnit * 10
    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 38,
        popupLoader.implicitHeight + full.header.height + Kirigami.Units.largeSpacing * 3)

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: root.module ? root.module.icon : ""
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                text: root.module ? root.module.title : ""
                elide: Text.ElideRight
            }
            PlasmaComponents.ToolButton {
                icon.name: "configure"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Configure")
                onClicked: Plasmoid.internalAction("configure").trigger()
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    contentItem: PlasmaComponents.ScrollView {
        id: scroll
        contentWidth: availableWidth
        implicitWidth: 0
        implicitHeight: 0
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        topPadding: Kirigami.Units.largeSpacing
        bottomPadding: Kirigami.Units.largeSpacing

        Loader {
            id: popupLoader
            width: scroll.contentWidth
            sourceComponent: root.module ? root.module.popup : null
        }
    }
}
