import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.quickcharts as Charts

// A framed history chart. Pass HistoryProxySources so history keeps accruing while the
// popup is closed, the way Stats charts are already full when you open them.
Rectangle {
    id: frame

    property var sources: []
    property var colors: []
    // Zero means scale to the data, for rates with no natural maximum.
    property real maximum: 100
    property bool stacked: false

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
    color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    border.width: 1
    radius: Kirigami.Units.cornerRadius

    Charts.LineChart {
        anchors.fill: parent
        anchors.margins: 1
        valueSources: frame.sources
        colorSource: Charts.ArraySource { array: frame.colors }
        stacked: frame.stacked
        smooth: true
        lineWidth: 1
        fillOpacity: 0.35
        direction: Charts.XYChart.ZeroAtEnd
        yRange {
            from: 0
            to: frame.maximum
            automatic: frame.maximum <= 0
        }
    }
}
