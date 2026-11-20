import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "StatsLogic.js" as Logic

PlasmoidItem {
    id: root

    readonly property string moduleId: Plasmoid.configuration.module
    readonly property var moduleInfo: Logic.moduleInfo(moduleId)
    readonly property string compactStyle: Logic.compactStyle(moduleId, Plasmoid.configuration.compactStyle)
    readonly property int interval: Math.max(500, Plasmoid.configuration.updateIntervalMs)
    readonly property var module: moduleLoader.item

    // Every sensor id ksystemstats knows, for discovering GPUs, disks, interfaces and chips.
    property var sensorIds: []

    function levelColor(level) {
        if (level === "critical")
            return Kirigami.Theme.negativeTextColor;
        if (level === "warning")
            return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.textColor;
    }

    // Fill for bars and rings: the accent until a reading crosses a threshold.
    function fillColor(level) {
        if (level === "critical" || level === "warning")
            return levelColor(level);
        return Kirigami.Theme.highlightColor;
    }

    Sensors.SensorTreeModel {
        id: tree
        onModelReset: catalogTimer.restart()
        onRowsInserted: catalogTimer.restart()
        onRowsRemoved: catalogTimer.restart()
    }

    Timer {
        id: catalogTimer
        interval: 250
        onTriggered: {
            const ids = [];
            const walk = function(parent) {
                for (let row = 0; row < tree.rowCount(parent); ++row) {
                    const index = tree.index(row, 0, parent);
                    const id = tree.data(index, Sensors.SensorTreeModel.SensorId);
                    if (id)
                        ids.push(id);
                    walk(index);
                }
            };
            walk(undefined);
            root.sensorIds = ids;
        }
    }

    // The module lives here, not in the popup, so its charts keep recording while closed.
    Loader {
        id: moduleLoader
        source: "modules/" + root.moduleInfo.file
    }

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    toolTipMainText: root.module ? root.module.title : ""
    toolTipSubText: root.module ? root.module.summary : ""

    Plasmoid.icon: root.module ? root.module.icon : "utilities-system-monitor"

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Open System Monitor")
            icon.name: "utilities-system-monitor"
            onTriggered: Qt.openUrlExternally("file:///usr/bin/plasma-systemmonitor")
        }
    ]

    Component.onCompleted: catalogTimer.start()
}
