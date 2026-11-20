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
    id: network

    readonly property var interfaceIds: Logic.interfaces(root.sensorIds)
    readonly property string configured: Plasmoid.configuration.networkInterface
    // Rates cover the configured interface, or every interface (Stats' default).
    readonly property string rateId: interfaceIds.indexOf(configured) >= 0 ? configured : "all"
    // Address details need a real interface: the configured one, else the first with an IPv4.
    readonly property string detailId: interfaceIds.indexOf(configured) >= 0 ? configured : autoDetailId
    property string autoDetailId: ""

    title: i18n("Network")
    icon: "network-wired"
    // Speed widgets carry no single fraction.
    fraction: NaN
    valueText: Logic.formatRate((download.value || 0) + (upload.value || 0))
    summary: i18n("Download: %1\nUpload: %2", downText, upText)
    upText: Logic.formatRate(upload.value)
    downText: Logic.formatRate(download.value)
    history: downloadHistory
    historyMaximum: 0

    Sensors.Sensor { id: download; sensorId: "network/" + network.rateId + "/download"; updateRateLimit: root.interval }
    Sensors.Sensor { id: upload; sensorId: "network/" + network.rateId + "/upload"; updateRateLimit: root.interval }
    Sensors.Sensor { id: totalDownload; sensorId: "network/" + network.rateId + "/totalDownload"; updateRateLimit: root.interval }
    Sensors.Sensor { id: totalUpload; sensorId: "network/" + network.rateId + "/totalUpload"; updateRateLimit: root.interval }

    Instantiator {
        id: addresses
        active: network.interfaceIds.indexOf(network.configured) < 0
        model: network.interfaceIds
        delegate: Sensors.Sensor {
            sensorId: "network/" + modelData + "/ipv4address"
            onValueChanged: pickDetail.restart()
        }
        onObjectAdded: pickDetail.restart()
        onObjectRemoved: pickDetail.restart()
    }
    // Re-pick whenever addresses come, go, or change, so the details follow the live link.
    Timer {
        id: pickDetail
        interval: 250
        onTriggered: {
            for (let i = 0; i < addresses.count; ++i) {
                const sensor = addresses.objectAt(i);
                if (sensor && sensor.value) {
                    network.autoDetailId = network.interfaceIds[i];
                    return;
                }
            }
            network.autoDetailId = "";
        }
    }

    Charts.HistoryProxySource {
        id: downloadHistory
        source: Charts.SingleValueSource { value: download.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }
    Charts.HistoryProxySource {
        id: uploadHistory
        source: Charts.SingleValueSource { value: upload.value || 0 }
        maximumHistory: 90
        interval: root.interval
        fillMode: Charts.HistoryProxySource.FillFromEnd
    }

    popup: Component {
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Sensors.Sensor { id: connection; sensorId: "network/" + network.detailId + "/network" }
            Sensors.Sensor { id: ipv4; sensorId: "network/" + network.detailId + "/ipv4withPrefixLength" }
            Sensors.Sensor { id: ipv6; sensorId: "network/" + network.detailId + "/ipv6address" }
            Sensors.Sensor { id: gateway; sensorId: "network/" + network.detailId + "/ipv4gateway" }
            Sensors.Sensor { id: dns; sensorId: "network/" + network.detailId + "/ipv4dns" }
            Sensors.Sensor { id: signal; sensorId: "network/" + network.detailId + "/signal" }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit

                Repeater {
                    model: [
                        {label: i18n("Downloading"), value: network.downText, color: Kirigami.Theme.highlightColor},
                        {label: i18n("Uploading"), value: network.upText, color: Kirigami.Theme.negativeTextColor},
                    ]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.value
                            font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.5)
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: modelData.color
                        }
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }
                    }
                }
            }

            Section {
                title: i18n("Usage history")
                HistoryChart {
                    sources: [downloadHistory, uploadHistory]
                    colors: [Kirigami.Theme.highlightColor, Kirigami.Theme.negativeTextColor]
                    maximum: 0
                }
                DetailRow { label: i18n("Downloaded since boot"); value: Logic.formatBytes(totalDownload.value); dotColor: Kirigami.Theme.highlightColor }
                DetailRow { label: i18n("Uploaded since boot"); value: Logic.formatBytes(totalUpload.value); dotColor: Kirigami.Theme.negativeTextColor }
            }

            Section {
                title: i18n("Details")
                visible: network.detailId !== ""
                DetailRow { label: i18n("Interface"); value: network.detailId }
                DetailRow { label: i18n("Connection"); value: connection.value || "–" }
                DetailRow { label: i18n("Signal"); value: signal.formattedValue; visible: signal.value > 0 }
                DetailRow { label: i18n("Local IP"); value: ipv4.value || "–" }
                DetailRow { label: i18n("IPv6"); value: ipv6.value || "–"; visible: !!ipv6.value }
                DetailRow { label: i18n("Gateway"); value: gateway.value || "–" }
                DetailRow { label: i18n("DNS"); value: dns.value || "–" }
            }

            Section {
                title: i18n("Top processes")
                visible: Plasmoid.configuration.topProcessCount > 0
                ProcessList {
                    attributes: ["netInbound", "netOutbound"]
                    format: value => Logic.formatRate(value)
                    count: Plasmoid.configuration.topProcessCount
                    active: network.active
                    interval: Math.max(1000, root.interval)
                }
            }
        }
    }
}
