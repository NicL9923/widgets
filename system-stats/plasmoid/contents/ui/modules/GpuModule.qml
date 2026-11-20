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
    id: gpu

    readonly property var gpuIds: Logic.gpus(root.sensorIds)
    readonly property string gpuId: gpuIds.indexOf(Plasmoid.configuration.gpuId) >= 0
        ? Plasmoid.configuration.gpuId : (gpuIds[0] || "gpu0")
    readonly property string prefix: "gpu/" + gpuId + "/"

    title: name.value || i18n("GPU")
    icon: "gpu"
    fraction: typeof usage.value === "number" ? usage.value / 100 : NaN
    summary: i18n("Utilization: %1\nMemory: %2 of %3\nTemperature: %4", valueText,
        Logic.formatBinary(usedVram.value), Logic.formatBinary(totalVram.value), temperature.formattedValue || "–")
    history: usageHistory

    Sensors.Sensor { id: name; sensorId: gpu.prefix + "name" }
    Sensors.Sensor { id: usage; sensorId: gpu.prefix + "usage"; updateRateLimit: root.interval }
    Sensors.Sensor { id: usedVram; sensorId: gpu.prefix + "usedVram"; updateRateLimit: root.interval }
    Sensors.Sensor { id: totalVram; sensorId: gpu.prefix + "totalVram" }
    Sensors.Sensor { id: temperature; sensorId: gpu.prefix + "temperature"; updateRateLimit: root.interval }
    Sensors.Sensor { id: power; sensorId: gpu.prefix + "power"; updateRateLimit: root.interval }
    Sensors.Sensor { id: coreClock; sensorId: gpu.prefix + "coreFrequency"; updateRateLimit: root.interval }
    Sensors.Sensor { id: memoryClock; sensorId: gpu.prefix + "memoryFrequency"; updateRateLimit: root.interval }

    readonly property real vramFraction: totalVram.value > 0 ? usedVram.value / totalVram.value : NaN

    Charts.HistoryProxySource {
        id: usageHistory
        source: Charts.SingleValueSource { value: usage.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }
    Charts.HistoryProxySource {
        id: vramHistory
        source: Charts.SingleValueSource { value: isNaN(gpu.vramFraction) ? 0 : gpu.vramFraction * 100 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }

    popup: Component {
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.gridUnit

                RingGauge {
                    fraction: gpu.fraction
                    known: !isNaN(gpu.fraction)
                    valueText: gpu.valueText
                    caption: i18n("Utilization")
                    color: root.fillColor(gpu.level)
                }
                RingGauge {
                    fraction: gpu.vramFraction
                    known: !isNaN(gpu.vramFraction)
                    valueText: Logic.formatPercent(gpu.vramFraction * 100)
                    caption: i18n("Memory")
                    color: Kirigami.Theme.visitedLinkColor
                }
                RingGauge {
                    fraction: (temperature.value || 0) / 100
                    known: typeof temperature.value === "number"
                    valueText: Logic.formatNumber(temperature.value, 0) + "°"
                    caption: i18n("Temperature")
                    color: root.fillColor(Logic.temperatureLevel(temperature.value))
                }
            }

            Section {
                title: i18n("Usage history")
                HistoryChart {
                    sources: [usageHistory, vramHistory]
                    colors: [Kirigami.Theme.highlightColor, Kirigami.Theme.visitedLinkColor]
                }
            }

            Section {
                title: i18n("Details")
                DetailRow { label: i18n("Utilization"); value: gpu.valueText; dotColor: Kirigami.Theme.highlightColor }
                DetailRow {
                    label: i18n("Memory")
                    value: i18n("%1 of %2", Logic.formatBinary(usedVram.value), Logic.formatBinary(totalVram.value))
                    dotColor: Kirigami.Theme.visitedLinkColor
                }
                DetailRow { label: i18n("Temperature"); value: temperature.formattedValue || "–" }
                DetailRow { label: i18n("Power"); value: power.formattedValue || "–"; visible: power.status === Sensors.Sensor.Ready }
                DetailRow { label: i18n("Core clock"); value: coreClock.formattedValue || "–"; visible: coreClock.status === Sensors.Sensor.Ready }
                DetailRow { label: i18n("Memory clock"); value: memoryClock.formattedValue || "–"; visible: memoryClock.status === Sensors.Sensor.Ready }
            }

            Section {
                title: i18n("Other GPUs")
                visible: gpu.gpuIds.length > 1
                Repeater {
                    model: gpu.gpuIds.filter(id => id !== gpu.gpuId)
                    DetailRow {
                        required property string modelData
                        Sensors.Sensor { id: otherName; sensorId: "gpu/" + modelData + "/name" }
                        Sensors.Sensor { id: otherUsage; sensorId: "gpu/" + modelData + "/usage"; updateRateLimit: root.interval }
                        Sensors.Sensor { id: otherTemperature; sensorId: "gpu/" + modelData + "/temperature"; updateRateLimit: root.interval }
                        label: otherName.value || modelData
                        value: Logic.formatPercent(otherUsage.value) + "  " + (otherTemperature.formattedValue || "")
                    }
                }
            }

            Section {
                title: i18n("Top processes by GPU memory")
                visible: Plasmoid.configuration.topProcessCount > 0
                ProcessList {
                    attributes: ["gpu_memory"]
                    format: value => Logic.formatBinary(value * 1024)
                    count: Plasmoid.configuration.topProcessCount
                    active: gpu.active
                    interval: Math.max(1000, root.interval)
                }
            }
        }
    }
}
