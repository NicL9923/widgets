// Pure helpers shared by the representations. Kept free of QML so node can test them.

const KIND_ICONS = {
    headset: "audio-headset",
    headphones: "audio-headphones",
    earbuds: "audio-headphones",
    mouse: "input-mouse",
    keyboard: "input-keyboard",
    gamepad: "input-gamepad",
    speaker: "audio-speakers",
};

function kindIcon(kind) {
    return KIND_ICONS[kind] || "battery";
}

// Throws on anything that is not the helper's contract, so the caller keeps its last good
// reading instead of rendering a guess.
function parsePayload(text) {
    const payload = JSON.parse(text);
    if (!payload || !Array.isArray(payload.devices) || !Array.isArray(payload.errors))
        throw new Error("not a device-battery payload");
    const devices = payload.devices.map(function(device) {
        if (typeof device.name !== "string" || typeof device.charging !== "boolean")
            throw new Error("malformed device");
        const percent = device.percent;
        if (percent !== null && (typeof percent !== "number" || percent < 0 || percent > 100))
            throw new Error("battery level out of range");
        const asleep = device.asleep === true;
        const updatedAt = typeof device.updatedAt === "string" ? device.updatedAt : null;
        return {id: String(device.id), name: device.name, kind: String(device.kind),
            percent: percent, charging: device.charging, source: String(device.source),
            asleep: asleep, updatedAt: updatedAt};
    });
    return {devices: devices, errors: payload.errors.map(error => String(error.source) + ": " + String(error.message))};
}

// "low" and "critical" map to theme roles in QML. Charging never reads as low.
function level(device, lowThreshold) {
    if (device.charging || device.percent === null)
        return "normal";
    if (device.percent <= Math.max(5, Math.round(lowThreshold / 2)))
        return "critical";
    if (device.percent <= lowThreshold)
        return "low";
    return "normal";
}

function percentText(device) {
    return device.percent === null ? "" : device.percent + "%";
}

// Whole minutes since an ISO timestamp, or null when it is missing or unparseable.
function minutesSince(iso, now) {
    if (!iso)
        return null;
    const then = Date.parse(iso);
    if (isNaN(then))
        return null;
    return Math.max(0, Math.floor((now - then) / 60000));
}
