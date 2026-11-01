const assert = require('node:assert/strict')
const { test } = require('node:test')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')

const model = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, '../ScrollEdgesModel.js'), 'utf8')
  .replace(/^\.pragma library\s*/, ''), model)
const pluginId = 'io.github.nodrej.scroll-edges'
const plain = value => JSON.parse(JSON.stringify(value))
const lookup = config => plain(model.settingsFor(JSON.stringify(config), pluginId))

test('reads a service-only entry in plugins and preserves all its keys', () => {
  const entry = { id: pluginId, peek: 28, color: '#abc', future: { nested: true } }
  assert.deepEqual(lookup({ plugins: [null, { id: 'other' }, entry] }), entry)
})

test('reads settings from each bar section without a plugins array', () => {
  for (const section of ['left', 'center', 'right']) {
    const entry = { id: pluginId, glowSize: 70, labelColor: '#123456' }
    assert.deepEqual(lookup({ bar: { layout: { [section]: [null, { id: 'other' }, entry] } } }), entry)
  }
})

test('bar settings win over plugins without merging stale overrides', () => {
  const barEntry = { id: pluginId, glowOpacity: 0, future: 42 }
  assert.deepEqual(lookup({
    bar: { layout: { right: [barEntry] } },
    plugins: [{ id: pluginId, peek: 99, color: '#fff' }]
  }), barEntry)
})

test('duplicate bar entries follow the host section and array order', () => {
  const first = { id: pluginId, peek: 1 }
  assert.deepEqual(lookup({ bar: { layout: {
    right: [{ id: pluginId, peek: 4 }],
    center: [{ id: pluginId, peek: 3 }],
    left: [first, { id: pluginId, peek: 2 }]
  } } }), first)
})

test('unrelated or malformed bar sections fall back to plugins', () => {
  const entry = { id: pluginId, glowSize: 90 }
  for (const bar of [null, [], {}, { layout: null }, { layout: {
    left: {}, center: 'invalid', right: [{ id: 'other' }]
  } }]) {
    assert.deepEqual(lookup({ bar, plugins: [entry] }), entry)
  }
})

test('bare bar ids take precedence but have no editable settings object', () => {
  assert.deepEqual(lookup({
    bar: { layout: { right: [pluginId] } },
    plugins: [{ id: pluginId, peek: 99 }]
  }), {})
})

test('canonical ids retain io.github. and do not strip invented prefixes', () => {
  assert.equal(model.canonicalWidgetId(pluginId), pluginId)
  assert.equal(model.canonicalWidgetId(null), '')
  const entry = { id: pluginId, peek: 12 }
  assert.deepEqual(lookup({
    bar: { layout: { left: [
      { id: 'plugin:' + pluginId, peek: 90 },
      { id: 'nodrej.scroll-edges', peek: 80 }
    ] } },
    plugins: [entry]
  }), entry)
  assert.deepEqual(plain(model.settingsFor(JSON.stringify({ plugins: [entry] }), 'plugin:' + pluginId)), {})
})

test('missing entries and unreadable configurations return defaults', () => {
  for (const config of [null, [], {}, { plugins: {} }, { plugins: [null, 'other'] }]) {
    assert.deepEqual(lookup(config), {})
  }
  for (const raw of ['', '{', undefined]) {
    assert.deepEqual(plain(model.settingsFor(raw, pluginId)), {})
  }
})
