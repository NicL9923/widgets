import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.quickcharts as Charts
import "StatsLogic.js" as Logic

// Stats-style menu bar widgets: mini, line, bar, speed and stack.
MouseArea {
    id: compact

    readonly property var module: root.module
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int thickness: vertical ? width : height
    // Two text lines must fit the panel; never grow past the theme's own fonts. Theme fonts
    // are usually set in points, so their pixelSize is -1; derive pixels from line height.
    readonly property int smallPixels: Math.max(7, Math.min(Math.round(themeSmall.height / 1.2),
        Math.floor(thickness * 0.34)))
    readonly property int valuePixels: Math.max(9, Math.min(Math.round(themeDefault.height / 1.2),
        Math.floor(thickness * 0.45)))
    readonly property string style: root.compactStyle
    readonly property bool showLabel: Plasmoid.configuration.showLabel

    Layout.minimumWidth: vertical ? 0 : content.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical ? Infinity : Layout.minimumWidth
    Layout.minimumHeight: vertical ? content.implicitHeight + Kirigami.Units.smallSpacing * 2 : 0
    Layout.preferredHeight: Layout.minimumHeight

    hoverEnabled: true
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: module ? module.title : ""
    Accessible.description: module ? module.summary : ""
    onClicked: root.expanded = !root.expanded
    Keys.onReturnPressed: root.expanded = !root.expanded
    Keys.onSpacePressed: root.expanded = !root.expanded

    FontMetrics {
        id: themeDefault
        font: Kirigami.Theme.defaultFont
    }
    FontMetrics {
        id: themeSmall
        font: Kirigami.Theme.smallFont
    }
    FontMetrics {
        id: valueMetrics
        font.pixelSize: compact.valuePixels
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
    FontMetrics {
        id: smallMetrics
        font.pixelSize: compact.smallPixels
        font.features: { "tnum": 1 }
    }

    Loader {
        id: content
        anchors.centerIn: parent
        active: compact.module !== null
        sourceComponent: ({mini: mini, line: line, bar: bar, speed: speed, stack: stack})[compact.style] || mini
    }

    // Label above, value below. Width is fixed to "100%" so the panel never jitters.
    Component {
        id: mini
        ColumnLayout {
            spacing: -Math.round(compact.smallPixels * 0.15)
            PlasmaComponents.Label {
                visible: compact.showLabel
                text: compact.module.label
                font.pixelSize: compact.smallPixels
                opacity: 0.8
                Layout.alignment: Qt.AlignLeft
            }
            PlasmaComponents.Label {
                Layout.preferredWidth: valueMetrics.advanceWidth("100%")
                text: compact.module.valueText
                font: valueMetrics.font
                color: root.levelColor(compact.module.level)
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    Component {
        id: line
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            ColumnLayout {
                spacing: 0
                visible: compact.showLabel
                PlasmaComponents.Label {
                    text: compact.module.label
                    font.pixelSize: compact.smallPixels
                    opacity: 0.8
                }
                PlasmaComponents.Label {
                    Layout.preferredWidth: valueMetrics.advanceWidth("100%")
                    text: compact.module.valueText
                    font: valueMetrics.font
                    color: root.levelColor(compact.module.level)
                }
            }
            Rectangle {
                Layout.preferredWidth: Math.round(compact.thickness * 1.4)
                Layout.preferredHeight: Math.round(compact.thickness * 0.62)
                color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.25)
                border.width: 1
                radius: 2
                Charts.LineChart {
                    anchors.fill: parent
                    anchors.margins: 1
                    valueSources: compact.module.history ? [compact.module.history] : []
                    colorSource: Charts.SingleValueSource { value: Kirigami.Theme.highlightColor }
                    lineWidth: 1
                    fillOpacity: 0.4
                    smooth: true
                    direction: Charts.XYChart.ZeroAtEnd
                    yRange {
                        from: 0
                        to: compact.module.historyMaximum
                        automatic: compact.module.historyMaximum <= 0
                    }
                }
            }
        }
    }

    // One bar per value: per-core for CPU, the main reading elsewhere.
    Component {
        id: bar
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                visible: compact.showLabel
                text: compact.module.label
                font.pixelSize: compact.smallPixels
                opacity: 0.8
                // Stats stacks the label's letters vertically beside the bars.
                rotation: compact.vertical ? 0 : -90
                Layout.preferredWidth: compact.vertical ? implicitWidth : implicitHeight
            }
            Row {
                id: bars
                readonly property var values: compact.module.bars
                readonly property int barWidth: values.length > 8 ? 2 : Math.max(3, Math.round(compact.thickness * 0.12))
                spacing: 1
                Layout.preferredHeight: Math.round(compact.thickness * 0.62)
                Repeater {
                    model: bars.values
                    Rectangle {
                        required property real modelData
                        width: bars.barWidth
                        height: bars.height
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: isNaN(modelData) ? 0 : Math.max(1, parent.height * Math.min(1, modelData))
                            color: root.fillColor(Logic.usageLevel(modelData))
                        }
                    }
                }
            }
        }
    }

    // Upload over download, fixed to the width of a three-digit rate.
    Component {
        id: speed
        GridLayout {
            columns: 2
            rowSpacing: -Math.round(compact.smallPixels * 0.1)
            columnSpacing: Kirigami.Units.smallSpacing / 2
            Repeater {
                model: [
                    {arrow: "↑", text: compact.module.upText, color: Kirigami.Theme.negativeTextColor},
                    {arrow: "↓", text: compact.module.downText, color: Kirigami.Theme.highlightColor},
                ]
                delegate: Component {
                    RowLayout {
                        required property var modelData
                        Layout.columnSpan: 2
                        spacing: Kirigami.Units.smallSpacing / 2
                        PlasmaComponents.Label {
                            text: modelData.arrow
                            font: smallMetrics.font
                            color: modelData.color
                        }
                        PlasmaComponents.Label {
                            Layout.preferredWidth: smallMetrics.advanceWidth("999 KB/s")
                            text: modelData.text
                            font: smallMetrics.font
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }

    // Two label-value rows, like Stats' sensors stack.
    Component {
        id: stack
        GridLayout {
            columns: 2
            rowSpacing: -Math.round(compact.smallPixels * 0.1)
            columnSpacing: Kirigami.Units.smallSpacing
            Repeater {
                model: compact.module.stackRows
                delegate: Component {
                    RowLayout {
                        required property var modelData
                        Layout.columnSpan: 2
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents.Label {
                            text: modelData.label
                            font: smallMetrics.font
                            opacity: 0.8
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            Layout.preferredWidth: smallMetrics.advanceWidth("100°")
                            text: modelData.value
                            font: smallMetrics.font
                            color: root.levelColor(modelData.level)
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
}
