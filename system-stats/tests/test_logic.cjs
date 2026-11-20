const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const logic = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../plasmoid/contents/ui/StatsLogic.js'), 'utf8'), logic);
const list = value => Array.from(value);

// Sensor ids as ksystemstats lists them on a real desktop, group patterns included.
const IDS = [
    'disk/all/usedPercent', 'disk/(?!all).*/usedPercent',
    'disk/18b3ae36/name', 'disk/18b3ae36/usedPercent', 'disk/5922ca44/usedPercent',
    'disk/nvme0n1/read', 'disk/nvme0n1/total',
    'gpu/all/usage', 'gpu/gpu\\d+/usage', 'gpu/gpu1/usage', 'gpu/gpu0/usage',
    'network/all/download', 'network/(?!all).*/download', 'network/enp111s0u2u2/download',
    'network/br-2e76a3496ef2/download', 'network/veth047a0bf/download', 'network/lo/download',
    'network/tailscale0/download', 'network/docker0/download',
    'lmsensors/nvme-pci-0200/temp1', 'lmsensors/corsairpsu-hid-3-3/fan1',
    'lmsensors/corsairpsu-hid-3-3/power1', 'lmsensors/corsairpsu-hid-3-3/in0',
    'lmsensors/spd5118-i2c-9-53/temp1', 'lmsensors/spd5118-i2c-9-51/temp1',
    'lmsensors/corsairpsu-hid-3-3/name',
];

test('usage colors change at 60% and 80%, like Stats', () => {
    assert.equal(logic.usageLevel(0.59), 'normal');
    assert.equal(logic.usageLevel(0.6), 'warning');
    assert.equal(logic.usageLevel(0.79), 'warning');
    assert.equal(logic.usageLevel(0.8), 'critical');
    assert.equal(logic.usageLevel(NaN), 'unknown');
});

test('memory pressure bands follow PSI some avg10', () => {
    assert.equal(logic.pressureLevel(9.9), 'normal');
    assert.equal(logic.pressureLevel(10), 'warning');
    assert.equal(logic.pressureLevel(40), 'critical');
    assert.equal(logic.pressureLevel(undefined), 'unknown');
});

test('temperatures only flag at 80 and 90 degrees', () => {
    assert.equal(logic.temperatureLevel(79.9), 'normal');
    assert.equal(logic.temperatureLevel(80), 'warning');
    assert.equal(logic.temperatureLevel(90), 'critical');
    assert.equal(logic.temperatureLevel(0), 'unknown');
});

test('rates use decimal units and never print NaN', () => {
    assert.equal(logic.formatRate(0), '0 B/s');
    assert.equal(logic.formatRate(999), '999 B/s');
    assert.equal(logic.formatRate(1000), '1.0 KB/s');
    assert.equal(logic.formatRate(12345678), '12 MB/s');
    assert.equal(logic.formatBytes(undefined), '–');
    assert.equal(logic.formatBinary(1536), '1.5 KiB');
    assert.equal(logic.formatPercentPrecise(0.44), '0.4%');
    assert.equal(logic.formatPercentPrecise(10.4), '10%');
});

test('discovery skips group patterns, aggregates, and virtual interfaces', () => {
    assert.deepEqual(list(logic.gpus(IDS)), ['gpu0', 'gpu1']);
    assert.deepEqual(list(logic.disks(IDS)), ['18b3ae36', '5922ca44']);
    assert.deepEqual(list(logic.interfaces(IDS)), ['enp111s0u2u2', 'tailscale0']);
});

test('hardware sensors group by kind in Stats order and ignore non-readings', () => {
    const groups = list(logic.hwmonGroups(IDS)).map(group => [group.kind, list(group.ids).length]);
    assert.deepEqual(groups, [['temperature', 3], ['power', 1], ['fan', 1], ['voltage', 1]]);
});

test('chips sharing a driver are numbered, single chips are not', () => {
    assert.equal(logic.chipName('lmsensors/nvme-pci-0200/temp1', IDS), 'nvme');
    assert.equal(logic.chipName('lmsensors/spd5118-i2c-9-51/temp1', IDS), 'spd5118 1');
    assert.equal(logic.chipName('lmsensors/spd5118-i2c-9-53/temp1', IDS), 'spd5118 2');
});

test('memory splits used into applications and the rest, available into cache and free', () => {
    const gib = 1024 ** 3;
    const s = logic.memorySegments(32 * gib, 6 * gib, 5 * gib, 10 * gib);
    assert.deepEqual([s.appBytes, s.otherBytes, s.cacheBytes, s.freeBytes].map(v => v / gib), [5, 1, 10, 16]);
    assert.equal(s.app + s.other + s.cache + s.free, 1);
    assert.equal(logic.memorySegments(0, 1, 1, 1), null);
    // Inconsistent samples never produce negative or overflowing segments.
    const odd = logic.memorySegments(8 * gib, 7 * gib, 9 * gib, 4 * gib);
    assert.deepEqual([odd.appBytes, odd.otherBytes, odd.cacheBytes, odd.freeBytes].map(v => v / gib), [7, 0, 1, 0]);
});

test('top processes drop idle rows and keep the busiest first', () => {
    const rows = [{name: 'a', value: 0}, {name: 'b', value: 5}, {name: 'c', value: 9}, {name: 'd', value: 1}];
    assert.deepEqual(list(logic.topRows(rows, 2)).map(row => row.name), ['c', 'b']);
    assert.deepEqual(list(logic.topRows([{name: 'idle', value: 0}], 5)), []);
});

test('process names collapse command lines but keep kernel threads', () => {
    assert.equal(logic.processName('/usr/bin/t3code-v2 --gpu-preferences=X'), 't3code-v2');
    assert.equal(logic.processName('[kworker/0:1]'), '[kworker/0:1]');
    assert.equal(logic.processName('(udev-worker)'), '(udev-worker)');
});

test('each module offers only styles it can draw, defaulting to its first', () => {
    assert.equal(logic.compactStyle('cpu', ''), 'mini');
    assert.equal(logic.compactStyle('cpu', 'bar'), 'bar');
    assert.equal(logic.compactStyle('disk', 'speed'), 'speed');
    assert.equal(logic.compactStyle('sensors', 'line'), 'stack');
    assert.equal(logic.compactStyle('network', 'mini'), 'speed');
    for (const id of ['cpu', 'gpu', 'memory', 'disk', 'network', 'sensors'])
        assert.ok(list(logic.moduleStyles(id)).length > 0);
});

test('a missing sample prints a dash, a real zero prints zero', () => {
    assert.equal(logic.formatNumber(undefined, 2), '–');
    assert.equal(logic.formatNumber(NaN, 1), '–');
    assert.equal(logic.formatNumber(0, 2), '0.00');
    assert.equal(logic.formatPercentPrecise(NaN), '–');
    assert.equal(logic.formatPercentPrecise(0), '0.0%');
});
