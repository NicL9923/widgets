import QtQuick
import org.kde.kirigami as Kirigami
import "../StatsLogic.js" as Logic

// What every module offers the panel and the popup. Modules are invisible data holders.
Item {
    id: module

    property string title
    property string label: root.moduleInfo.label
    property string icon: "utilities-system-monitor"
    property string summary

    // Main reading as a 0-1 fraction; NaN until the first value arrives. A sensor's value is
    // undefined until its first sample, even after its metadata reports it ready, so modules
    // check for a number rather than for Sensor.Ready.
    property real fraction: NaN
    property string valueText: Logic.formatPercent(fraction * 100)
    property string level: Logic.usageLevel(fraction)

    // Compact line chart: the history of the main reading.
    property QtObject history: null
    property real historyMaximum: 100
    property color historyColor: Kirigami.Theme.highlightColor

    // Compact bar chart: one bar per value. Defaults to the main reading alone.
    property var bars: [fraction]

    // Speed and stack styles.
    property string upText
    property string downText
    property var stackRows: []

    property Component popup
    readonly property bool active: root.expanded

    visible: false
}
