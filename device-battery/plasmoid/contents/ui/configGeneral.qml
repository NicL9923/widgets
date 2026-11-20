import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_pollIntervalSeconds: pollInterval.value
    property alias cfg_lowThreshold: lowThreshold.value
    property alias cfg_showNames: showNames.checked
    property alias cfg_helperCommand: helperCommand.text

    QQC2.SpinBox {
        id: pollInterval
        Kirigami.FormData.label: i18n("Check every:")
        from: 5
        to: 600
        stepSize: 5
        textFromValue: function(value) { return i18np("%1 second", "%1 seconds", value); }
        valueFromText: function(text) { return parseInt(text); }
    }

    QQC2.SpinBox {
        id: lowThreshold
        Kirigami.FormData.label: i18n("Warn at or below:")
        from: 5
        to: 50
        stepSize: 5
        textFromValue: function(value) { return i18n("%1%", value); }
        valueFromText: function(text) { return parseInt(text); }
    }

    QQC2.CheckBox {
        id: showNames
        Kirigami.FormData.label: i18n("Panel:")
        text: i18n("Show device names")
    }

    QQC2.TextField {
        id: helperCommand
        Kirigami.FormData.label: i18n("Helper command:")
        Layout.fillWidth: true
    }
}
