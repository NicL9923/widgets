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
    id: memory

    title: i18n("Memory")
    icon: "memory"
    fraction: usedPercent.status === Sensors.Sensor.Ready ? usedPercent.value / 100 : NaN
    summary: i18n("Used: %1 of %2\nPressure: %3", Logic.formatBinary(used.value),
        Logic.formatBinary(total.value), pressureText)
    history: usageHistory

    readonly property string pressure: pressureSome.status === Sensors.Sensor.Ready
        ? Logic.pressureLevel(pressureSome.value) : "unknown"
    readonly property string pressureText: ({normal: i18n("normal"), warning: i18n("warning"),
        critical: i18n("critical")})[pressure] || "–"
    readonly property var segments: Logic.memorySegments(total.value, used.value, application.value, cache.value)

    Sensors.Sensor { id: total; sensorId: "memory/physical/total" }
    Sensors.Sensor { id: used; sensorId: "memory/physical/used"; updateRateLimit: root.interval }
    Sensors.Sensor { id: usedPercent; sensorId: "memory/physical/usedPercent"; updateRateLimit: root.interval }
    Sensors.Sensor { id: application; sensorId: "memory/physical/application"; updateRateLimit: root.interval }
    Sensors.Sensor { id: cache; sensorId: "memory/physical/cache"; updateRateLimit: root.interval }
    Sensors.Sensor { id: swapUsed; sensorId: "memory/swap/used"; updateRateLimit: root.interval }
    Sensors.Sensor { id: swapTotal; sensorId: "memory/swap/total" }
    Sensors.Sensor { id: pressureSome; sensorId: "pressure/memory/some10Sec"; updateRateLimit: root.interval }

    Charts.HistoryProxySource {
        id: usageHistory
        source: Charts.SingleValueSource { value: usedPercent.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }

    popup: Component {
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.gridUnit * 2

                RingGauge {
                    fraction: memory.fraction
                    known: !isNaN(memory.fraction)
                    valueText: memory.valueText
                    caption: i18n("Usage")
                    color: root.fillColor(memory.level)
                }
                PressureGauge {
                    level: memory.pressure
                }
            }

            Section {
                title: i18n("Usage history")
                HistoryChart {
                    sources: [usageHistory]
                    colors: [Kirigami.Theme.highlightColor]
                }
            }

            Section {
                title: i18n("Details")
                DetailRow {
                    label: i18n("Used")
                    value: i18n("%1 of %2", Logic.formatBinary(used.value), Logic.formatBinary(total.value))
                }
                StackedBar {
                    visible: memory.segments !== null
                    segments: memory.segments ? [
                        {fraction: memory.segments.app, color: Kirigami.Theme.highlightColor},
                        {fraction: memory.segments.other, color: Kirigami.Theme.neutralTextColor},
                        {fraction: memory.segments.cache, color: Kirigami.Theme.visitedLinkColor},
                    ] : []
                }
                DetailRow { label: i18n("Applications"); value: Logic.formatBinary(memory.segments ? memory.segments.appBytes : NaN); dotColor: Kirigami.Theme.highlightColor }
                DetailRow { label: i18n("Kernel and shared"); value: Logic.formatBinary(memory.segments ? memory.segments.otherBytes : NaN); dotColor: Kirigami.Theme.neutralTextColor }
                DetailRow { label: i18n("Cached"); value: Logic.formatBinary(memory.segments ? memory.segments.cacheBytes : NaN); dotColor: Kirigami.Theme.visitedLinkColor }
                DetailRow { label: i18n("Free"); value: Logic.formatBinary(memory.segments ? memory.segments.freeBytes : NaN); dotColor: Qt.alpha(Kirigami.Theme.textColor, 0.3) }
                DetailRow {
                    label: i18n("Swap")
                    value: i18n("%1 of %2", Logic.formatBinary(swapUsed.value), Logic.formatBinary(swapTotal.value))
                }
                DetailRow {
                    label: i18n("Stalled on memory (10 s)")
                    value: pressureSome.status === Sensors.Sensor.Ready ? Number(pressureSome.value).toFixed(1) + "%" : "–"
                    valueColor: root.levelColor(memory.pressure)
                }
            }

            Section {
                title: i18n("Top processes")
                visible: Plasmoid.configuration.topProcessCount > 0
                ProcessList {
                    attributes: ["memory"]
                    format: value => Logic.formatBinary(value * 1024)
                    count: Plasmoid.configuration.topProcessCount
                    active: memory.active
                    interval: Math.max(1000, root.interval)
                }
            }
        }
    }
}
