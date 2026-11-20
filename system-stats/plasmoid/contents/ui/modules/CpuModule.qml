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
    id: cpu

    title: i18n("CPU")
    icon: "cpu"
    fraction: usage.status === Sensors.Sensor.Ready ? usage.value / 100 : NaN
    summary: i18n("Usage: %1\nTemperature: %2\nLoad average: %3", valueText,
        temperature.formattedValue || "–", load1.formattedValue || "–")
    history: usageHistory
    bars: root.compactStyle === "bar" || active ? coreValues : [fraction]

    property var coreValues: []

    Sensors.Sensor { id: usage; sensorId: "cpu/all/usage"; updateRateLimit: root.interval }
    Sensors.Sensor { id: system; sensorId: "cpu/all/system"; updateRateLimit: root.interval }
    Sensors.Sensor { id: user; sensorId: "cpu/all/user"; updateRateLimit: root.interval }
    Sensors.Sensor { id: wait; sensorId: "cpu/all/wait"; updateRateLimit: root.interval }
    Sensors.Sensor { id: temperature; sensorId: "cpu/all/averageTemperature"; updateRateLimit: root.interval }
    Sensors.Sensor { id: maxTemperature; sensorId: "cpu/all/maximumTemperature"; updateRateLimit: root.interval }
    Sensors.Sensor { id: frequency; sensorId: "cpu/all/averageFrequency"; updateRateLimit: root.interval }
    Sensors.Sensor { id: maxFrequency; sensorId: "cpu/all/maximumFrequency"; updateRateLimit: root.interval }
    Sensors.Sensor { id: coreCount; sensorId: "cpu/all/coreCount" }
    Sensors.Sensor { id: load1; sensorId: "cpu/loadaverages/loadaverage1"; updateRateLimit: root.interval }
    Sensors.Sensor { id: load5; sensorId: "cpu/loadaverages/loadaverage5"; updateRateLimit: root.interval }
    Sensors.Sensor { id: load15; sensorId: "cpu/loadaverages/loadaverage15"; updateRateLimit: root.interval }
    Sensors.Sensor { id: uptime; sensorId: "os/system/uptime" }

    Charts.HistoryProxySource {
        id: usageHistory
        source: Charts.SingleValueSource { value: usage.value || 0 }
        maximumHistory: 60
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }
    Charts.HistoryProxySource {
        id: systemHistory
        source: Charts.SingleValueSource { value: system.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }
    Charts.HistoryProxySource {
        id: userHistory
        source: Charts.SingleValueSource { value: user.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }

    // Per-core sensors only exist while something shows them.
    Instantiator {
        id: cores
        active: root.compactStyle === "bar" || cpu.active
        model: coreCount.value || 0
        delegate: Sensors.Sensor { sensorId: "cpu/cpu" + index + "/usage"; updateRateLimit: root.interval }
    }

    Timer {
        interval: root.interval
        running: cores.active
        repeat: true
        onTriggered: {
            const values = [];
            for (let i = 0; i < cores.count; ++i) {
                const core = cores.objectAt(i);
                values.push(core && core.status === Sensors.Sensor.Ready ? core.value / 100 : 0);
            }
            cpu.coreValues = values;
        }
    }

    popup: Component {
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.gridUnit

                RingGauge {
                    fraction: cpu.fraction
                    known: !isNaN(cpu.fraction)
                    valueText: cpu.valueText
                    caption: i18n("Usage")
                    color: Kirigami.Theme.highlightColor
                }
                RingGauge {
                    fraction: (temperature.value || 0) / 100
                    known: temperature.status === Sensors.Sensor.Ready
                    valueText: Math.round(temperature.value) + "°"
                    caption: i18n("Temperature")
                    color: root.fillColor(Logic.temperatureLevel(temperature.value))
                }
                RingGauge {
                    fraction: maxFrequency.value > 0 ? frequency.value / maxFrequency.value : 0
                    known: frequency.status === Sensors.Sensor.Ready
                    valueText: (frequency.value / 1000).toFixed(1)
                    caption: i18n("GHz")
                    color: Kirigami.Theme.visitedLinkColor
                }
            }

            Section {
                title: i18n("Usage history")
                HistoryChart {
                    sources: [systemHistory, userHistory]
                    colors: [Kirigami.Theme.negativeTextColor, Kirigami.Theme.highlightColor]
                    stacked: true
                }
                // One column per logical core, like Stats' per-core chart.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    Row {
                        id: coreRow
                        anchors.fill: parent
                        spacing: 1
                        Repeater {
                            model: cpu.coreValues
                            Item {
                                required property real modelData
                                width: (coreRow.width - (cpu.coreValues.length - 1)) / Math.max(1, cpu.coreValues.length)
                                height: coreRow.height
                                Rectangle {
                                    anchors.fill: parent
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: parent.height * Math.min(1, modelData)
                                    color: root.fillColor(Logic.usageLevel(modelData))
                                }
                            }
                        }
                    }
                }
            }

            Section {
                title: i18n("Details")
                DetailRow { label: i18n("System"); value: Logic.formatPercentPrecise(system.value); dotColor: Kirigami.Theme.negativeTextColor }
                DetailRow { label: i18n("User"); value: Logic.formatPercentPrecise(user.value); dotColor: Kirigami.Theme.highlightColor }
                DetailRow { label: i18n("I/O wait"); value: Logic.formatPercentPrecise(wait.value) }
                DetailRow { label: i18n("Idle"); value: Logic.formatPercentPrecise(100 - (usage.value || 0)); dotColor: Qt.alpha(Kirigami.Theme.textColor, 0.3) }
                DetailRow { label: i18n("Hottest core sensor"); value: maxTemperature.formattedValue || "–" }
                DetailRow { label: i18n("Logical cores"); value: String(coreCount.value || "–") }
                DetailRow { label: i18n("Uptime"); value: Logic.formatDuration(uptime.value) }
            }

            Section {
                title: i18n("Average load")
                DetailRow { label: i18n("1 minute"); value: Number(load1.value || 0).toFixed(2) }
                DetailRow { label: i18n("5 minutes"); value: Number(load5.value || 0).toFixed(2) }
                DetailRow { label: i18n("15 minutes"); value: Number(load15.value || 0).toFixed(2) }
            }

            Section {
                title: i18n("Top processes")
                ProcessList {
                    attributes: ["usage"]
                    format: value => Logic.formatPercent(value)
                    count: Plasmoid.configuration.topProcessCount
                    active: cpu.active
                    interval: Math.max(1000, root.interval)
                }
            }
        }
    }
}
