// todo.txt-compatible storage for the three task sections.
//
//   x 2026-10-16 Ship it     → done (completion date kept)
//   (A) Write the README     → next (any priority counts as next)
//   Buy milk                 → backlog
//
// File order is display order within each section.

// On-screen order, top to bottom.
var SECTIONS = [
  { key: "next", label: "Next", empty: "Press n on a backlog task to queue it here" },
  { key: "backlog", label: "Backlog", empty: "Type a task below and press Enter" },
  { key: "done", label: "Done", empty: "Press Space on a task to finish it" }
]

function dataDir(xdgDataHome, home) {
  return (xdgDataHome || home + "/.local/share") + "/omarchy-todo"
}

function today() {
  var d = new Date()
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function parseLine(line) {
  var raw = String(line || "").replace(/\s+$/, "")
  if (!raw.trim()) return null

  var done = /^x\s+(?:(\d{4}-\d{2}-\d{2})\s+)?(?:\d{4}-\d{2}-\d{2}\s+)?(.*)$/.exec(raw)
  if (done) return { section: "done", completed: done[1] || "", text: done[2].trim() }

  var next = /^\([A-Z]\)\s+(.*)$/.exec(raw)
  if (next) return { section: "next", completed: "", text: next[1].trim() }

  return { section: "backlog", completed: "", text: raw.trim() }
}

function parse(text) {
  var lines = String(text || "").split(/\r?\n/)
  var tasks = []
  for (var i = 0; i < lines.length; i++) {
    var task = parseLine(lines[i])
    if (task && task.text) tasks.push(task)
  }
  return tasks
}

function formatTask(task) {
  if (task.section === "done") return "x " + (task.completed || today()) + " " + task.text
  if (task.section === "next") return "(A) " + task.text
  return task.text
}

// Written grouped next → backlog → done so the file reads well in an editor.
function serialize(tasks) {
  var order = ["next", "backlog", "done"]
  var out = []
  for (var s = 0; s < order.length; s++)
    for (var i = 0; i < tasks.length; i++)
      if (tasks[i].section === order[s]) out.push(formatTask(tasks[i]))
  return out.length ? out.join("\n") + "\n" : ""
}

// Typed text can carry its own section: "(A) foo" lands in next.
function fromInput(text, section) {
  var parsed = parseLine(text)
  if (!parsed || !parsed.text) return null
  if (parsed.section === "backlog") parsed.section = section || "backlog"
  if (parsed.section === "done" && !parsed.completed) parsed.completed = today()
  return parsed
}

function count(tasks, section) {
  var n = 0
  for (var i = 0; i < tasks.length; i++) if (tasks[i].section === section) n++
  return n
}

// Rows in on-screen order (next, backlog, done). Each carries its task
// index and its own row position.
function displayRows(tasks) {
  var buckets = {}
  for (var s = 0; s < SECTIONS.length; s++) buckets[SECTIONS[s].key] = []
  for (var i = 0; i < tasks.length; i++)
    buckets[tasks[i].section].push({ index: i, text: tasks[i].text, section: tasks[i].section, completed: tasks[i].completed })
  var rows = []
  for (var k = 0; k < SECTIONS.length; k++) rows = rows.concat(buckets[SECTIONS[k].key])
  for (var r = 0; r < rows.length; r++) rows[r].row = r
  return rows
}

// Moves a task to a section. Newly done tasks go to the top of done;
// tasks moved to next/backlog go to the bottom of that section.
function moveTo(tasks, index, section) {
  var next = tasks.slice()
  var old = next.splice(index, 1)[0]
  if (!old || old.section === section) return { tasks: tasks, index: index }
  var task = { section: section, completed: section === "done" ? today() : "", text: old.text }

  var at = next.length
  if (section === "done") {
    for (var i = 0; i < next.length; i++) if (next[i].section === "done") { at = i; break }
  } else {
    for (var j = next.length - 1; j >= 0; j--) if (next[j].section === section) { at = j + 1; break }
  }
  next.splice(at, 0, task)
  return { tasks: next, index: at }
}

// Swaps a task with its neighbour in the same section (delta -1 or +1).
function reorder(tasks, index, delta) {
  var section = tasks[index] && tasks[index].section
  for (var j = index + delta; j >= 0 && j < tasks.length; j += delta) {
    if (tasks[j].section !== section) continue
    var next = tasks.slice()
    var tmp = next[index]
    next[index] = next[j]
    next[j] = tmp
    return { tasks: next, index: j }
  }
  return { tasks: tasks, index: index }
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    serialize: serialize,
    fromInput: fromInput,
    count: count,
    dataDir: dataDir,
    displayRows: displayRows,
    moveTo: moveTo,
    reorder: reorder
  }
}
