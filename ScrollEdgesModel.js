.pragma library

// Pure geometry for the scroll-edge indicators. Kept out of the QML so the
// window-counting rules can be read — and corrected — without wading through
// layer-shell plumbing.

// Hyprland reports a monitor's size in physical pixels alongside a scale and a
// transform, but positions windows in the logical space it lays out in. The
// odd transforms are the 90°/270° rotations, which swap the axes: the portrait
// Dell is a 3840x2160 panel that windows see as 1728x3072.
function logicalBounds(monitor) {
  var scale = Number(monitor.scale) || 1
  var rotated = (Number(monitor.transform) || 0) % 2 === 1
  var width = (rotated ? monitor.height : monitor.width) / scale
  var height = (rotated ? monitor.width : monitor.height) / scale

  return {
    left: monitor.x,
    top: monitor.y,
    right: monitor.x + width,
    bottom: monitor.y + height
  }
}

function emptyCounts() {
  return {
    left: 0, right: 0, top: 0, bottom: 0,
    total: 0,
    fullscreen: false,
    // Hyprland orders this [left, top, right, bottom] — the same order the
    // indicators are inset by, so the bar never gets drawn over.
    reserved: [0, 0, 0, 0]
  }
}

// Which windows on a monitor's active workspace have been scrolled far enough
// past an edge to count as hidden.
//
// `peek` is the whole judgement call: a window still showing more than that
// many pixels is visible enough to speak for itself, and one showing less is
// the sliver you have to hunt for at the screen edge — exactly what these
// indicators exist to replace.
function scan(clients, monitor, peek) {
  var counts = emptyCounts()
  if (!monitor || !Array.isArray(clients)) return counts

  if (Array.isArray(monitor.reserved) && monitor.reserved.length === 4) {
    counts.reserved = monitor.reserved
  }

  var workspaceId = monitor.activeWorkspace ? monitor.activeWorkspace.id : null
  if (workspaceId === null || workspaceId === undefined) return counts

  var bounds = logicalBounds(monitor)

  for (var i = 0; i < clients.length; i++) {
    var client = clients[i]
    if (!client || client.monitor !== monitor.id) continue
    if (!client.workspace || client.workspace.id !== workspaceId) continue
    if (!client.mapped || client.hidden) continue

    // A fullscreen or maximized window covers the row it was scrolled out of,
    // so there is no edge left worth annotating. Hyprland uses 0 for neither.
    if (Number(client.fullscreen) > 0) {
      counts.fullscreen = true
      continue
    }

    // Floating windows sit outside the scroll row entirely. One dragged half
    // off-screen says nothing about how many columns the row holds.
    if (client.floating) continue
    if (!Array.isArray(client.at) || !Array.isArray(client.size)) continue

    var x = client.at[0]
    var y = client.at[1]
    var right = x + client.size[0]
    var bottom = y + client.size[1]

    // Each axis is judged on its own, so a rotated monitor scrolling top to
    // bottom needs no special case here.
    if (right <= bounds.left + peek) counts.left++
    else if (x >= bounds.right - peek) counts.right++

    if (bottom <= bounds.top + peek) counts.top++
    else if (y >= bounds.bottom - peek) counts.bottom++
  }

  counts.total = counts.left + counts.right + counts.top + counts.bottom
  return counts
}

// Monitor name -> counts, for every monitor Hyprland currently reports.
function scanAll(clients, monitors, peek) {
  var byName = {}
  if (!Array.isArray(monitors)) return byName

  for (var i = 0; i < monitors.length; i++) {
    var monitor = monitors[i]
    if (!monitor || !monitor.name) continue
    byName[monitor.name] = scan(clients, monitor, peek)
  }

  return byName
}

// This plugin's own entry in shell.json, which is where its tunables live.
// A file that is missing, half-written, or simply doesn't mention the plugin
// is not an error — it means "use the defaults", so every failure returns {}.
function settingsFor(raw, pluginId) {
  var config
  try {
    config = JSON.parse(raw || "{}")
  } catch (e) {
    return {}
  }

  var entries = (config && Array.isArray(config.plugins)) ? config.plugins : []
  for (var i = 0; i < entries.length; i++) {
    if (entries[i] && entries[i].id === pluginId) return entries[i]
  }

  return {}
}
