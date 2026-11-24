const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const state = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../plasmoid/contents/ui/BatteryState.js'), 'utf8'), state);

const mouse = {id: 'razer:00c1', name: 'Razer Viper V3 Pro', kind: 'mouse', percent: 90, charging: false, source: 'razer'};
const payload = devices => JSON.stringify({version: 1, devices, errors: []});

test('parses the helper contract', () => {
    const reading = state.parsePayload(payload([mouse]));
    assert.equal(reading.devices[0].percent, 90);
    assert.deepEqual(Array.from(reading.errors), []);
});

test('charging headset without a level keeps a null percent', () => {
    const reading = state.parsePayload(payload([{...mouse, percent: null, charging: true}]));
    assert.equal(reading.devices[0].percent, null);
    assert.equal(state.percentText(reading.devices[0]), '');
});

test('rejects payloads that would render a guessed level', () => {
    assert.throws(() => state.parsePayload('{}'), /not a device-battery payload/);
    assert.throws(() => state.parsePayload(payload([{...mouse, percent: 101}])), /out of range/);
    assert.throws(() => state.parsePayload(payload([{...mouse, percent: '90'}])), /out of range/);
    assert.throws(() => state.parsePayload(payload([{...mouse, charging: 'no'}])), /malformed/);
    assert.throws(() => state.parsePayload('not json'));
});

test('low and critical levels sit on both sides of the threshold', () => {
    const at = percent => state.level({...mouse, percent}, 20);
    assert.equal(at(21), 'normal');
    assert.equal(at(20), 'low');
    assert.equal(at(11), 'low');
    assert.equal(at(10), 'critical');
    assert.equal(state.level({...mouse, percent: 3, charging: true}, 20), 'normal');
});

test('asleep and reading time pass through, defaulting safely', () => {
    const asleep = state.parsePayload(payload([{...mouse, percent: 88, asleep: true, updatedAt: '2026-11-20T00:50:00+00:00'}])).devices[0];
    assert.equal(asleep.asleep, true);
    assert.equal(state.minutesSince(asleep.updatedAt, Date.parse('2026-11-20T01:00:30+00:00')), 10);
    const older = state.parsePayload(payload([mouse])).devices[0];
    assert.equal(older.asleep, false);
    assert.equal(older.updatedAt, null);
    assert.equal(state.minutesSince('garbage', Date.now()), null);
});
