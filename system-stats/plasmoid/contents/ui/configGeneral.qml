import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "StatsLogic.js" as Logic

Kirigami.FormLayout {
    id: page

    property string cfg_module
    property string cfg_compactStyle
    property alias cfg_showLabel: showLabel.checked
    property alias cfg_updateIntervalMs: interval.value
    property alias cfg_topProcessCount: processCount.value
    property alias cfg_gpuId: gpuId.text
    property alias cfg_diskId: diskId.text
    property alias cfg_networkInterface: networkInterface.text

    readonly property var modules: [
        {value: "cpu", text: i18n("CPU")},
        {value: "gpu", text: i18n("GPU")},
        {value: "memory", text: i18n("Memory")},
        {value: "disk", text: i18n("Disk")},
        {value: "network", text: i18n("Network")},
        {value: "sensors", text: i18n("Sensors")},
    ]
    readonly property var styleNames: ({
        mini: i18n("Mini"),
        line: i18n("Line chart"),
        bar: i18n("Bar chart"),
        speed: i18n("Speed"),
        stack: i18n("Stack"),
    })
    // Only the styles the chosen module can draw, its default first.
    readonly property var styles: Logic.moduleStyles(cfg_module).map(function(style, index) {
        return {value: style, text: index === 0 ? i18n("%1 (default)", styleNames[style]) : styleNames[style]};
    })

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Shows:")
        model: page.modules
        textRole: "text"
        valueRole: "value"
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_module)
        onActivated: page.cfg_module = currentValue
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Panel style:")
        model: page.styles
        textRole: "text"
        valueRole: "value"
        currentIndex: Math.max(0, indexOfValue(Logic.compactStyle(page.cfg_module, page.cfg_compactStyle)))
        onActivated: page.cfg_compactStyle = currentValue
    }

    QQC2.CheckBox {
        id: showLabel
        text: i18n("Show module label")
    }

    QQC2.SpinBox {
        id: interval
        Kirigami.FormData.label: i18n("Update every:")
        from: 500
        to: 10000
        stepSize: 500
        textFromValue: function(value) { return i18n("%1 s", (value / 1000).toLocaleString(Qt.locale(), "f", 1)); }
        valueFromText: function(text) { return Math.round(Number.fromLocaleString(Qt.locale(), text.replace(/[^0-9.,]/g, "")) * 1000); }
    }

    QQC2.SpinBox {
        id: processCount
        Kirigami.FormData.label: i18n("Top processes:")
        from: 0
        to: 15
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Advanced")
    }

    QQC2.TextField {
        id: gpuId
        Kirigami.FormData.label: i18n("GPU:")
        placeholderText: i18n("First GPU (for example gpu0)")
    }

    QQC2.TextField {
        id: diskId
        Kirigami.FormData.label: i18n("Disk:")
        placeholderText: i18n("Largest disk")
    }

    QQC2.TextField {
        id: networkInterface
        Kirigami.FormData.label: i18n("Network interface:")
        placeholderText: i18n("All interfaces")
    }
}
