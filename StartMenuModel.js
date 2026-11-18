// The Start menu's own state, kept apart from the dock's pins: which apps are
// pinned to Start, which were opened lately, how "All" is shown, and how apps
// are grouped. It lives in ~/.config/omarchy/dock-start.json:
//
//   {
//     "pinned": ["org.gnome.Nautilus", ...],   // omit to use the defaults
//     "recent": ["obsidian", ...],             // newest first, kept by the menu
//     "view": "category" | "list" | "grid",
//     "groups": { "obsidian": "Notes" }        // per-app group overrides
//   }

var VIEWS = ["category", "list", "grid"]
var MAX_RECENT = 12
var OTHER = "Other"

// One slot per default pin; the first installed alternative wins.
var DEFAULT_PINNED = [
  ["org.gnome.Nautilus"],
  ["com.mitchellh.ghostty", "foot", "alacritty", "kitty"],
  ["google-chrome", "com.google.Chrome", "omarchy-browser", "chromium", "firefox"],
  ["com.microsoft.VSCode", "code"],
  ["obsidian"],
  ["libreoffice-writer"],
  ["libreoffice-calc"],
  ["libreoffice-impress"],
  ["org.gnome.Evince", "org.gnome.Papers"],
  ["vlc", "mpv"],
  ["com.obsproject.Studio"],
  ["com.github.PintaProject.Pinta"],
  ["localsend"],
  ["Discord"],
  ["btop"],
  ["org.gnome.DiskUtility"]
]

// Display order; the first group whose categories match an app claims it.
var GROUP_RULES = [
  { name: "Productivity", categories: ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Calendar", "ProjectManagement", "Viewer"] },
  { name: "Development", categories: ["Development", "IDE", "TextEditor", "Debugger", "WebDevelopment"] },
  { name: "Internet", categories: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "FileTransfer", "VideoConference"] },
  { name: "Media", categories: ["AudioVideo", "Audio", "Video", "Player", "Recorder", "Music"] },
  { name: "Creativity", categories: ["Graphics", "Photography", "2DGraphics", "RasterGraphics", "VectorGraphics"] },
  { name: "Games", categories: ["Game"] },
  { name: "System", categories: ["Settings", "System", "Monitor", "Security", "PackageManager", "HardwareSettings"] },
  { name: "Utilities & Tools", categories: ["Utility", "FileManager", "TerminalEmulator", "Accessibility", "Archiving", "Calculator"] }
]

function normalizeId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function uniqueIds(list) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var id = normalizeId(list[i])
    if (id && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

function emptyState() {
  return { pinned: null, recent: [], view: "category", groups: {} }
}

function parseState(raw) {
  var state = emptyState()
  var data = null
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return state
  }
  if (!data || typeof data !== "object") return state
  if (Array.isArray(data.pinned)) state.pinned = uniqueIds(data.pinned)
  if (Array.isArray(data.recent)) state.recent = uniqueIds(data.recent).slice(0, MAX_RECENT)
  if (VIEWS.indexOf(data.view) >= 0) state.view = data.view
  if (data.groups && typeof data.groups === "object") {
    for (var key in data.groups) {
      var group = String(data.groups[key] || "").trim()
      if (group) state.groups[normalizeId(key)] = group
    }
  }
  return state
}

function serializeState(state) {
  var out = { view: state.view, recent: state.recent, groups: state.groups }
  if (state.pinned) out.pinned = state.pinned
  return JSON.stringify(out, null, 2) + "\n"
}

// The pins to show: the saved ones, or the defaults that are installed.
function pinnedIds(state, exists) {
  if (state.pinned) return state.pinned
  var out = []
  for (var i = 0; i < DEFAULT_PINNED.length; i++) {
    for (var j = 0; j < DEFAULT_PINNED[i].length; j++) {
      var id = DEFAULT_PINNED[i][j]
      if (exists(id)) {
        if (out.indexOf(id) === -1) out.push(id)
        break
      }
    }
  }
  return out
}

function withPinned(state, ids) {
  var next = JSON.parse(JSON.stringify(state))
  next.pinned = uniqueIds(ids)
  return next
}

function withRecent(state, id) {
  id = normalizeId(id)
  if (!id) return state
  var next = JSON.parse(JSON.stringify(state))
  next.recent = [id].concat(state.recent.filter(function(other) { return other !== id })).slice(0, MAX_RECENT)
  return next
}

function withView(state, view) {
  var next = JSON.parse(JSON.stringify(state))
  if (VIEWS.indexOf(view) >= 0) next.view = view
  return next
}

function groupOf(entry, overrides) {
  var id = normalizeId(entry && entry.id)
  if (overrides && overrides[id]) return overrides[id]
  var categories = (entry && entry.categories) || []
  for (var i = 0; i < GROUP_RULES.length; i++) {
    for (var j = 0; j < categories.length; j++) {
      if (GROUP_RULES[i].categories.indexOf(categories[j]) >= 0) return GROUP_RULES[i].name
    }
  }
  return OTHER
}

// Entries (already sorted by name) split into groups: the built-in groups in
// their order, then any custom ones alphabetically, and "Other" last.
function buildGroups(entries, overrides) {
  var byName = {}
  for (var i = 0; i < entries.length; i++) {
    var name = groupOf(entries[i], overrides)
    if (!byName[name]) byName[name] = []
    byName[name].push(entries[i])
  }
  var builtIn = GROUP_RULES.map(function(rule) { return rule.name })
  var custom = Object.keys(byName).filter(function(name) { return builtIn.indexOf(name) < 0 && name !== OTHER }).sort()
  var order = builtIn.concat(custom, [OTHER])
  var out = []
  for (var k = 0; k < order.length; k++) {
    if (byName[order[k]]) out.push({ name: order[k], entries: byName[order[k]] })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    serializeState: serializeState,
    pinnedIds: pinnedIds,
    withPinned: withPinned,
    withRecent: withRecent,
    withView: withView,
    groupOf: groupOf,
    buildGroups: buildGroups,
    emptyState: emptyState
  }
}
