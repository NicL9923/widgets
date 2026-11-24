import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.process as Process
import org.kde.plasma.components as PlasmaComponents
import "../StatsLogic.js" as Logic

// Stats' "Top processes": the busiest processes by one or two summed attributes.
// The process model only runs while the popup is open.
ColumnLayout {
    id: list

    property var attributes: ["usage"]
    property var format: value => String(value)
    property int count: 5
    property bool active: false
    property int interval: 2000
    property var rows: []

    readonly property bool sampling: active && count > 0

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    Process.ProcessDataModel {
        id: processes
        enabled: list.sampling
        enabledAttributes: ["name"].concat(list.attributes)
    }

    function refresh() {
        const valueRole = Process.ProcessDataModel.Value;
        const sampled = [];
        for (let row = 0; row < processes.rowCount(); ++row) {
            let total = 0;
            for (let column = 1; column <= list.attributes.length; ++column)
                total += Number(processes.data(processes.index(row, column), valueRole)) || 0;
            sampled.push({name: Logic.processName(processes.data(processes.index(row, 0), valueRole)), value: total});
        }
        list.rows = Logic.topRows(sampled, list.count);
    }

    Timer {
        interval: list.interval
        running: list.sampling
        repeat: true
        triggeredOnStart: true
        onTriggered: list.refresh()
    }

    Repeater {
        model: list.rows

        RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: modelData.name
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                text: list.format(modelData.value)
                font.features: { "tnum": 1 }
                opacity: 0.8
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: list.rows.length === 0
        text: i18n("Nothing active")
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.6
    }
}
