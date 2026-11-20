// Pure helpers for the System Stats applet. Kept free of QML so node can test them.

// Each instance shows one module, like one Stats menu bar item.
const MODULES = {
    cpu: {file: "CpuModule.qml", label: "CPU", styles: ["mini", "line", "bar"]},
    gpu: {file: "GpuModule.qml", label: "GPU", styles: ["mini", "line", "bar"]},
    memory: {file: "MemoryModule.qml", label: "RAM", styles: ["mini", "line", "bar"]},
    disk: {file: "DiskModule.qml", label: "SSD", styles: ["mini", "bar", "speed"]},
    network: {file: "NetworkModule.qml", label: "NET", styles: ["speed", "line"]},
    sensors: {file: "SensorsModule.qml", label: "SNS", styles: ["stack", "mini"]},
};

function moduleInfo(id) {
    return MODULES[id] || MODULES.cpu;
}

// The first listed style is the module's default. The config page offers the same list.
function moduleStyles(id) {
    return moduleInfo(id).styles;
}

function compactStyle(moduleId, configured) {
    const styles = moduleStyles(moduleId);
    return styles.indexOf(configured) >= 0 ? configured : styles[0];
}

// Load averages and other plain numbers: a dash until a sample arrives.
function formatNumber(value, decimals) {
    return typeof value === "number" && isFinite(value) ? value.toFixed(decimals) : "–";
}

// Stats' Mini widget colors utilization at 60% and 80%.
function usageLevel(fraction) {
    if (!(fraction >= 0))
        return "unknown";
    if (fraction >= 0.8)
        return "critical";
    if (fraction >= 0.6)
        return "warning";
    return "normal";
}

// Linux PSI "some" over 10 seconds: the share of time at least one task stalled on memory.
// macOS reports pressure as three bands; these cut-offs are a judgment call that keeps
// ordinary page-cache churn green and sustained reclaim stalls red.
function pressureLevel(someAvg10) {
    if (!(someAvg10 >= 0))
        return "unknown";
    if (someAvg10 >= 40)
        return "critical";
    if (someAvg10 >= 10)
        return "warning";
    return "normal";
}

// Decimal units, as Stats and macOS use.
function formatBytes(bytes, decimals) {
    if (!(bytes >= 0))
        return "–";
    const units = ["B", "KB", "MB", "GB", "TB", "PB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1000 && unit < units.length - 1) {
        value /= 1000;
        unit += 1;
    }
    const places = unit === 0 ? 0 : (decimals === undefined ? (value < 10 ? 1 : 0) : decimals);
    return value.toFixed(places) + " " + units[unit];
}

function formatRate(bytesPerSecond) {
    return formatBytes(bytesPerSecond) + "/s";
}

function formatPercent(value) {
    if (!(value >= 0))
        return "–";
    return Math.round(value) + "%";
}

// Details rows: one decimal below 10%, so an idle CPU reads 0.4%, not 0%.
function formatPercentPrecise(value) {
    if (!(value >= 0))
        return "–";
    return value < 10 ? value.toFixed(1) + "%" : Math.round(value) + "%";
}

// Temperatures in degrees Celsius. Most desktop parts run in the 60s and 70s under load,
// so only flag what is actually hot.
function temperatureLevel(celsius) {
    if (!(celsius > 0))
        return "unknown";
    if (celsius >= 90)
        return "critical";
    if (celsius >= 80)
        return "warning";
    return "normal";
}

function formatDuration(seconds) {
    if (!(seconds >= 0))
        return "–";
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor(seconds % 86400 / 3600);
    const minutes = Math.floor(seconds % 3600 / 60);
    if (days > 0)
        return days + "d " + hours + "h " + minutes + "m";
    if (hours > 0)
        return hours + "h " + minutes + "m";
    return minutes + "m";
}

// Process names: kernel threads stay as they are; command lines collapse to the executable.
function processName(name) {
    const text = String(name || "");
    if (text.startsWith("[") || text.startsWith("("))
        return text;
    const first = text.split(" ")[0];
    return first.substring(first.lastIndexOf("/") + 1) || text;
}

// Pick the top rows by value, dropping zeros so an idle list reads as empty, not padded.
function topRows(rows, count) {
    return rows.filter(row => row.value > 0)
        .sort((a, b) => b.value - a.value)
        .slice(0, count);
}

// The catalog lists every sensor id. Group entries carry regular expressions; skip them.
function concreteIds(ids) {
    return ids.filter(id => !/[()\\*+?\[\]]/.test(id));
}

function objects(ids, category, exclude) {
    const seen = [];
    for (const id of concreteIds(ids)) {
        const parts = id.split("/");
        if (parts.length < 3 || parts[0] !== category || parts[1] === "all")
            continue;
        if (exclude && exclude.test(parts[1]))
            continue;
        if (seen.indexOf(parts[1]) < 0)
            seen.push(parts[1]);
    }
    return seen;
}

function gpus(ids) {
    return objects(ids, "gpu").sort();
}

// Disks with a filesystem report usedPercent; whole devices and swap do not.
function disks(ids) {
    return objects(ids, "disk").filter(disk => ids.indexOf("disk/" + disk + "/usedPercent") >= 0);
}

// Container bridges, veth pairs and loopback are noise in a menu bar.
const VIRTUAL_INTERFACE = /^(lo|br-|veth|docker|virbr|vnet|podman|cni|flannel|tun|tap)/;

function interfaces(ids) {
    return objects(ids, "network", VIRTUAL_INTERFACE);
}

const HWMON_KINDS = [
    {prefix: "temp", kind: "temperature", title: "Temperature"},
    {prefix: "power", kind: "power", title: "Power"},
    {prefix: "fan", kind: "fan", title: "Fans"},
    {prefix: "in", kind: "voltage", title: "Voltage"},
    {prefix: "curr", kind: "current", title: "Current"},
];

function hwmonKind(sensorName) {
    for (const entry of HWMON_KINDS) {
        if (new RegExp("^" + entry.prefix + "\\d+$").test(sensorName))
            return entry.kind;
    }
    return "";
}

// Group lm-sensors readings by kind, in the order Stats shows them.
function hwmonGroups(ids) {
    const groups = HWMON_KINDS.map(entry => ({kind: entry.kind, title: entry.title, ids: []}));
    for (const id of concreteIds(ids)) {
        const parts = id.split("/");
        if (parts.length !== 3 || parts[0] !== "lmsensors")
            continue;
        const kind = hwmonKind(parts[2]);
        const group = groups.find(entry => entry.kind === kind);
        if (group)
            group.ids.push(id);
    }
    return groups.filter(group => group.ids.length > 0);
}

// "nvme-pci-0200" -> "nvme". Chips that share a driver, like one spd5118 per memory
// module, are numbered in sensor-id order: "spd5118 1", "spd5118 2".
function chipName(sensorId, allIds) {
    const chip = String(sensorId).split("/")[1] || "";
    const base = chip.split("-")[0];
    const siblings = [];
    for (const id of concreteIds(allIds || [])) {
        const parts = id.split("/");
        if (parts[0] === "lmsensors" && parts.length === 3 && parts[1].split("-")[0] === base
                && siblings.indexOf(parts[1]) < 0)
            siblings.push(parts[1]);
    }
    if (siblings.length < 2)
        return base;
    siblings.sort();
    return base + " " + (siblings.indexOf(chip) + 1);
}

// Memory sizes in binary units, labelled as such.
function formatBinary(bytes) {
    if (!(bytes >= 0))
        return "–";
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
    }
    return value.toFixed(unit === 0 ? 0 : 1) + " " + units[unit];
}

// ksystemstats reports "free" as available memory and "used" as total minus available.
// Split used into application memory and the rest (kernel, shared), and available into
// page cache and truly free pages, like Stats' App / Wired / Cached / Free breakdown.
function memorySegments(total, used, application, cache) {
    if (!(total > 0) || !(used >= 0))
        return null;
    const app = Math.max(0, Math.min(application || 0, used));
    const other = Math.max(0, used - app);
    const cached = Math.max(0, Math.min(cache || 0, total - used));
    const free = Math.max(0, total - used - cached);
    return {app: app / total, other: other / total, cache: cached / total, free: free / total,
        appBytes: app, otherBytes: other, cacheBytes: cached, freeBytes: free};
}
