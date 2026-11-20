import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "BatteryState.js" as BatteryState

PlasmoidItem {
    id: root

    property var devices: []
    property var errors: []
    property string helperError: ""
    property bool loaded: false
    property bool busy: false

    readonly property string helper: Plasmoid.configuration.helperCommand
    readonly property int pollSeconds: Math.max(5, Plasmoid.configuration.pollIntervalSeconds)
    readonly property int lowThreshold: Plasmoid.configuration.lowThreshold
    readonly property bool editing: Plasmoid.containment && Plasmoid.containment.corona
        ? Plasmoid.containment.corona.editMode : false

    function levelColor(device) {
        const level = BatteryState.level(device, root.lowThreshold);
        if (level === "critical")
            return Kirigami.Theme.negativeTextColor;
        if (level === "low")
            return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.textColor;
    }

    function ageText(device) {
        const minutes = BatteryState.minutesSince(device.updatedAt, Date.now());
        if (minutes === null)
            return "";
        if (minutes < 1)
            return i18n("just now");
        if (minutes < 60)
            return i18np("%1 minute ago", "%1 minutes ago", minutes);
        return i18np("%1 hour ago", "%1 hours ago", Math.floor(minutes / 60));
    }

    function stateText(device) {
        if (device.asleep)
            return device.percent === null ? i18n("Asleep") : i18n("Asleep, read %1", root.ageText(device));
        return device.charging ? i18n("Charging") : "";
    }

    function deviceSummary(device) {
        const level = device.percent === null ? "" : i18n("%1%", device.percent);
        const state = root.stateText(device);
        return device.name + ": " + [level, state].filter(part => part !== "").join(", ");
    }

    function poll() {
        if (root.busy || root.helper === "")
            return;
        root.busy = true;
        executable.connectSource(root.helper);
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            disconnectSource(source);
            root.busy = false;
            if (source !== root.helper)
                return;
            const stdout = (data["stdout"] || "").trim();
            try {
                const reading = BatteryState.parsePayload(stdout);
                root.devices = reading.devices;
                root.errors = reading.errors;
                root.helperError = "";
            } catch (error) {
                const stderr = (data["stderr"] || "").trim();
                // Keep showing the last good reading; a helper hiccup is not a disconnect.
                root.helperError = stderr || i18n("Could not read the battery helper's output");
            }
            root.loaded = true;
        }
    }

    Timer {
        interval: root.pollSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    onHelperChanged: {
        root.devices = [];
        root.loaded = false;
        root.poll();
    }
    onExpandedChanged: if (root.expanded) root.poll()

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    toolTipMainText: i18n("Device battery")
    toolTipSubText: {
        if (root.helperError !== "")
            return root.helperError;
        if (!root.loaded)
            return i18n("Loading…");
        if (root.devices.length === 0)
            return i18n("No connected devices report a battery");
        return root.devices.map(device => root.deviceSummary(device)).join("\n");
    }

    // Nothing connected and nothing wrong: stay out of the way.
    Plasmoid.status: {
        if (root.devices.some(device => BatteryState.level(device, root.lowThreshold) !== "normal"))
            return PlasmaCore.Types.NeedsAttentionStatus;
        if (root.loaded && root.devices.length === 0 && root.helperError === "")
            return PlasmaCore.Types.PassiveStatus;
        return PlasmaCore.Types.ActiveStatus;
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            enabled: !root.busy
            onTriggered: root.poll()
        }
    ]
}
