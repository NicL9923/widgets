import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.quickcharts as Charts
import "../components"
import "../StatsLogic.js" as Logic

ModuleBase {
    id: disk

    readonly property var diskIds: Logic.disks(root.sensorIds)
    // The configured disk, else the largest one: on most machines, the root filesystem.
    readonly property string diskId: diskIds.indexOf(Plasmoid.configuration.diskId) >= 0
        ? Plasmoid.configuration.diskId : autoDiskId
    property string autoDiskId: ""

    title: selected && selected.name ? i18n("Disk: %1", selected.name) : i18n("Disk")
    icon: "drive-harddisk"
    fraction: selected && typeof selected.usedPercent === "number" ? selected.usedPercent / 100 : NaN
    summary: i18n("%1 used of %2\nRead: %3\nWrite: %4", Logic.formatBytes(selected ? selected.used : NaN),
        Logic.formatBytes(selected ? selected.total : NaN), Logic.formatRate(read.value), Logic.formatRate(write.value))
    history: readHistory
    historyMaximum: 0
    upText: Logic.formatRate(write.value)
    downText: Logic.formatRate(read.value)

    // Pick the largest disk, and pick again whenever a size arrives or a disk comes or goes.
    Instantiator {
        id: totals
        active: disk.diskIds.indexOf(Plasmoid.configuration.diskId) < 0
        model: disk.diskIds
        delegate: Sensors.Sensor {
            sensorId: "disk/" + modelData + "/total"
            onValueChanged: chooser.restart()
        }
        onObjectAdded: chooser.restart()
        onObjectRemoved: chooser.restart()
    }
    Timer {
        id: chooser
        interval: 250
        onTriggered: {
            let best = "";
            let bestTotal = -1;
            for (let i = 0; i < totals.count; ++i) {
                const sensor = totals.objectAt(i);
                if (sensor && sensor.value > bestTotal) {
                    bestTotal = sensor.value;
                    best = disk.diskIds[i];
                }
            }
            disk.autoDiskId = best;
        }
    }

    // A fresh set of sensors per selected disk. A Sensor keeps its last value when its id
    // changes, so reusing one would show the previous disk's numbers until new data came.
    property Item selected: null
    Instantiator {
        model: disk.diskId !== "" ? [disk.diskId] : []
        delegate: Item {
            required property string modelData
            readonly property var name: nameSensor.value
            readonly property var usedPercent: percentSensor.value
            readonly property var used: usedSensor.value
            readonly property var total: totalSensor.value
            Sensors.Sensor { id: nameSensor; sensorId: "disk/" + modelData + "/name" }
            Sensors.Sensor { id: percentSensor; sensorId: "disk/" + modelData + "/usedPercent"; updateRateLimit: root.interval }
            Sensors.Sensor { id: usedSensor; sensorId: "disk/" + modelData + "/used"; updateRateLimit: root.interval }
            Sensors.Sensor { id: totalSensor; sensorId: "disk/" + modelData + "/total" }
        }
        onObjectAdded: (index, object) => disk.selected = object
        onObjectRemoved: (index, object) => {
            if (disk.selected === object)
                disk.selected = null;
        }
    }
    Sensors.Sensor { id: read; sensorId: "disk/all/read"; updateRateLimit: root.interval }
    Sensors.Sensor { id: write; sensorId: "disk/all/write"; updateRateLimit: root.interval }

    Charts.HistoryProxySource {
        id: readHistory
        source: Charts.SingleValueSource { value: read.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }
    Charts.HistoryProxySource {
        id: writeHistory
        source: Charts.SingleValueSource { value: write.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }

    popup: Component {
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: disk.diskIds

                ColumnLayout {
                    id: card

                    required property string modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Sensors.Sensor { id: cardName; sensorId: "disk/" + card.modelData + "/name" }
                    Sensors.Sensor { id: cardUsed; sensorId: "disk/" + card.modelData + "/used"; updateRateLimit: root.interval }
                    Sensors.Sensor { id: cardTotal; sensorId: "disk/" + card.modelData + "/total" }
                    Sensors.Sensor { id: cardPercent; sensorId: "disk/" + card.modelData + "/usedPercent"; updateRateLimit: root.interval }

                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            source: "drive-harddisk"
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: cardName.value || card.modelData
                            elide: Text.ElideRight
                            font.weight: card.modelData === disk.diskId ? Font.DemiBold : Font.Normal
                        }
                        PlasmaComponents.Label {
                            text: Logic.formatPercent(cardPercent.value)
                            font.features: { "tnum": 1 }
                        }
                    }
                    StackedBar {
                        segments: [{fraction: (cardPercent.value || 0) / 100,
                            color: root.fillColor(Logic.usageLevel((cardPercent.value || 0) / 100))}]
                    }
                    PlasmaComponents.Label {
                        text: i18n("%1 free of %2", Logic.formatBytes(cardTotal.value - cardUsed.value), Logic.formatBytes(cardTotal.value))
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }
                }
            }

            Section {
                title: i18n("Read and write")
                HistoryChart {
                    sources: [readHistory, writeHistory]
                    colors: [Kirigami.Theme.highlightColor, Kirigami.Theme.negativeTextColor]
                    maximum: 0
                }
                DetailRow { label: i18n("Read"); value: Logic.formatRate(read.value); dotColor: Kirigami.Theme.highlightColor }
                DetailRow { label: i18n("Write"); value: Logic.formatRate(write.value); dotColor: Kirigami.Theme.negativeTextColor }
            }

            Section {
                title: i18n("Top processes")
                visible: Plasmoid.configuration.topProcessCount > 0
                ProcessList {
                    attributes: ["ioCharactersActuallyReadRate", "ioCharactersActuallyWrittenRate"]
                    format: value => Logic.formatRate(value)
                    count: Plasmoid.configuration.topProcessCount
                    active: disk.active
                    interval: Math.max(1000, root.interval)
                }
            }
        }
    }
}
