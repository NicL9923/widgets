// Plasma shell script: a macOS-style menu bar and dock on every screen. Each dock lists every
// window, so a window on any monitor can be raised from the monitor you are looking at.
// Run through org.kde.PlasmaShell.evaluateScript. Settings worth keeping (task manager
// launchers, weather location, clock, launcher icon, AI Usage) carry over from the panels
// it replaces. Re-running it rebuilds the same layout.

var MENU_BAR_HEIGHT = 34;
var DOCK_HEIGHT = 58;
var STATS_MODULES = ["cpu", "gpu", "memory", "disk", "network", "sensors"];

// CARRY is prepended by apply.sh: {pluginId: {group: {key: value}}}, read from the panels
// this script replaces. Reading config back through the scripting API flattens string lists,
// so apply.sh parses the config file instead.
function restore(widget, saved, overrides) {
    var merged = {};
    var group, key;
    for (group in saved) {
        merged[group] = merged[group] || {};
        for (key in saved[group])
            merged[group][key] = saved[group][key];
    }
    for (group in overrides || {}) {
        merged[group] = merged[group] || {};
        for (key in overrides[group])
            merged[group][key] = overrides[group][key];
    }
    for (group in merged) {
        widget.currentConfigGroup = [group];
        for (key in merged[group])
            widget.writeConfig(key, merged[group][key]);
    }
    widget.reloadConfig();
}

var old = panels();
for (var r = 0; r < old.length; ++r)
    old[r].remove();

function add(panel, type, overrides) {
    var widget = panel.addWidget(type);
    restore(widget, CARRY[type] || {}, overrides);
    return widget;
}

for (var s = 0; s < screenCount; ++s) {
    var bar = new Panel;
    bar.screen = s;
    bar.location = "top";
    bar.height = MENU_BAR_HEIGHT;
    bar.floating = false;
    bar.lengthMode = "fill";
    bar.hiding = "none";

    add(bar, "org.kde.plasma.kickoff");
    add(bar, "org.kde.plasma.panelspacer");
    for (var m = 0; m < STATS_MODULES.length; ++m)
        add(bar, "com.nicl9923.systemstats", {General: {module: STATS_MODULES[m]}});
    add(bar, "com.nicl9923.devicebattery");
    add(bar, "com.nicl9923.aiusage");
    add(bar, "weather.widget.plus", {Appearance: {widgetFontSize: 12, widgetIconSize: 16}});
    add(bar, "org.kde.plasma.systemtray");
    add(bar, "org.kde.plasma.digitalclock", {Appearance: {
        dateDisplayFormat: "BesideTime", dateFormat: "custom", customDateFormat: "ddd MMM d",
        // One point under the 10 pt system font. The stock clock sizes date and time together.
        autoFontAndSize: false, fontSize: 9}});

    var dock = new Panel;
    dock.screen = s;
    dock.location = "bottom";
    dock.height = DOCK_HEIGHT;
    dock.floating = true;
    dock.lengthMode = "fit";
    dock.alignment = "center";
    dock.hiding = "none";
    add(dock, "org.kde.plasma.icontasks", {General: {
        showOnlyCurrentScreen: false, groupingStrategy: 1}});
}
print("menu bars and docks: " + screenCount);
