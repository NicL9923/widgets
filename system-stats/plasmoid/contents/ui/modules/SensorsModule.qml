import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "../components"
import "../StatsLogic.js" as Logic

ModuleBase {
    id: sensors

    readonly property string gpuId: Logic.gpus(root.sensorIds)[0] || "gpu0"

    title: i18n("Sensors")
    icon: "temperature-normal"
    readonly property bool cpuReady: cpuTemperature.status === Sensors.Sensor.Ready
    fraction: cpuReady ? cpuTemperature.value / 100 : NaN
    level: Logic.temperatureLevel(Math.max(cpuTemperature.value || 0, gpuTemperature.value || 0))
    valueText: cpuReady ? Math.round(cpuTemperature.value) + "°" : "–"
    summary: i18n("CPU: %1\nGPU: %2", cpuTemperature.formattedValue || "–", gpuTemperature.formattedValue || "–")
    stackRows: [
        {label: i18n("CPU"), value: cpuTemperature.status === Sensors.Sensor.Ready ? Math.round(cpuTemperature.value) + "°" : "–",
            level: Logic.temperatureLevel(cpuTemperature.value)},
        {label: i18n("GPU"), value: gpuTemperature.status === Sensors.Sensor.Ready ? Math.round(gpuTemperature.value) + "°" : "–",
            level: Logic.temperatureLevel(gpuTemperature.value)},
    ]

    Sensors.Sensor { id: cpuTemperature; sensorId: "cpu/all/averageTemperature"; updateRateLimit: root.interval }
    Sensors.Sensor { id: gpuTemperature; sensorId: "gpu/" + sensors.gpuId + "/temperature"; updateRateLimit: root.interval }

    popup: Component {
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Section {
                title: i18n("Processor and graphics")
                Repeater {
                    model: ["cpu/all/averageTemperature", "cpu/all/maximumTemperature"]
                        .concat(Logic.gpus(root.sensorIds).map(id => "gpu/" + id + "/temperature"))
                        .concat(Logic.gpus(root.sensorIds).map(id => "gpu/" + id + "/power"))
                    SensorRow {}
                }
            }

            Repeater {
                model: Logic.hwmonGroups(root.sensorIds)

                Section {
                    required property var modelData
                    title: modelData.title
                    Repeater {
                        model: modelData.ids
                        SensorRow { showChip: true }
                    }
                }
            }
        }
    }

    component SensorRow: DetailRow {
        id: row

        required property string modelData
        property bool showChip: false

        visible: reading.status === Sensors.Sensor.Ready
        label: (showChip ? Logic.chipName(modelData, root.sensorIds) + " " : "") + reading.name
        value: reading.formattedValue
        valueColor: reading.unit === 1000 /* Celsius */
            ? root.levelColor(Logic.temperatureLevel(reading.value)) : Kirigami.Theme.textColor

        Sensors.Sensor { id: reading; sensorId: row.modelData; updateRateLimit: root.interval }
    }
}
