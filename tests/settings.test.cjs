const assert = require('node:assert/strict')
const { test } = require('node:test')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')

const model = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, '../SettingsModel.js'), 'utf8')
  .replace(/^\.pragma library\s*/, ''), model)
const plain = value => JSON.parse(JSON.stringify(value))

test('hex accepts short and full RGB, trims whitespace, and rejects other formats', () => {
  for (const value of ['#abc', '#ABCDEF', '#123456', ' #aB9 ']) {
    assert.equal(model.hex(value), value.trim())
  }
  for (const value of ['', '#12', '#1234', '#12345678', '#ggg', 'red', 'abc', null, 123]) {
    assert.equal(model.hex(value), '')
  }
})

test('numeric settings clamp to form limits, round pixels, and retain zero strength', () => {
  assert.deepEqual(plain(model.values({ peek: -10, glowSize: 999, glowOpacity: 0 })), {
    peek: 0, glowSize: 160, glowOpacity: 0, color: '', labelColor: ''
  })
  assert.equal(model.values({ peek: 999 }).peek, 300)
  assert.equal(model.values({ glowSize: 0 }).glowSize, 4)
  assert.equal(model.values({ glowSize: 19.6 }).glowSize, 20)
  assert.equal(model.values({ glowOpacity: 2 }).glowOpacity, 1)
  assert.equal(model.values({ glowOpacity: -1 }).glowOpacity, 0)
  assert.equal(model.values({ peek: '28.6' }).peek, 29)
})

test('missing and malformed values use fresh defaults', () => {
  assert.deepEqual(plain(model.values({ peek: null, glowSize: false, glowOpacity: 'oops' })), plain(model.defaults()))
  for (const value of [NaN, Infinity, '', ' ', undefined, {}, []]) {
    assert.equal(model.clamp(value, 0, 300, 56, true), 56)
  }
  const defaults = model.defaults()
  defaults.peek = 0
  assert.equal(model.defaults().peek, 56)
})

test('follow theme removes both color keys and preserves unknown entry keys', () => {
  const entry = { id: 'io.github.nodrej.scroll-edges', enabled: true, future: { nested: 7 }, color: '#fff', labelColor: '#000' }
  const before = JSON.stringify(entry)
  const result = plain(model.build(entry, model.defaults()))
  assert.equal('color' in result, false)
  assert.equal('labelColor' in result, false)
  assert.equal(result.id, entry.id)
  assert.equal(result.enabled, true)
  assert.deepEqual(result.future, { nested: 7 })
  assert.equal(JSON.stringify(entry), before)
})

test('valid overrides save while invalid hex never replaces a saved value', () => {
  const draft = { ...plain(model.defaults()), color: ' #F0a ', labelColor: '#badinput' }
  const result = plain(model.build({ labelColor: '#112233', other: 42 }, draft))
  assert.equal(result.color, '#F0a')
  assert.equal(result.labelColor, '#112233')
  assert.equal(result.other, 42)
  assert.equal('labelColor' in model.build({}, draft), false)
})

test('reset removes exactly the five managed keys without mutating the entry', () => {
  const entry = { id: 'plugin', enabled: false, other: { color: '#fff' }, peek: 1, glowSize: 5, glowOpacity: 0, color: '#fff', labelColor: '#000' }
  assert.deepEqual(plain(model.reset(entry)), { id: 'plugin', enabled: false, other: { color: '#fff' } })
  assert.equal(entry.peek, 1)
  assert.deepEqual(plain(model.reset({})), {})
})
