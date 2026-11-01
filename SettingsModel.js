.pragma library

// The form owns only these five keys. Copying the rest on every save keeps
// host flags and settings from a newer plugin version intact.
function copy(entry) {
  var result = {}
  if (entry && typeof entry === "object" && !Array.isArray(entry)) {
    for (var key in entry) {
      if (Object.prototype.hasOwnProperty.call(entry, key)) result[key] = entry[key]
    }
  }
  return result
}

function defaults() {
  return { peek: 56, glowSize: 44, glowOpacity: 0.62, color: "", labelColor: "" }
}

function hex(value) {
  if (typeof value !== "string") return ""
  var trimmed = value.trim()
  return /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(trimmed) ? trimmed : ""
}

function clamp(value, minimum, maximum, fallback, integer) {
  // Empty fields, null and booleans are not deliberate numeric settings.
  var number = typeof value === "number" || (typeof value === "string" && value.trim() !== "")
    ? Number(value) : NaN
  if (!isFinite(number)) number = fallback
  number = Math.max(minimum, Math.min(maximum, number))
  return integer ? Math.round(number) : number
}

function values(entry) {
  var source = entry || {}
  var result = defaults()
  result.peek = clamp(source.peek, 0, 300, result.peek, true)
  result.glowSize = clamp(source.glowSize, 4, 160, result.glowSize, true)
  result.glowOpacity = clamp(source.glowOpacity, 0, 1, result.glowOpacity, false)
  result.color = hex(source.color)
  result.labelColor = hex(source.labelColor)
  return result
}

function reset(entry) {
  var result = copy(entry)
  var keys = ["peek", "glowSize", "glowOpacity", "color", "labelColor"]
  for (var i = 0; i < keys.length; i++) delete result[keys[i]]
  return result
}

function build(entry, draft) {
  var result = copy(entry)
  var normalized = values(draft)
  result.peek = normalized.peek
  result.glowSize = normalized.glowSize
  result.glowOpacity = normalized.glowOpacity
  var colors = ["color", "labelColor"]
  for (var i = 0; i < colors.length; i++) {
    var key = colors[i]
    // Empty means follow theme. Invalid input leaves the previous key alone,
    // so another control can save safely while a hex field is unfinished.
    if (draft[key] === "") delete result[key]
    else if (normalized[key] !== "") result[key] = normalized[key]
  }
  return result
}
