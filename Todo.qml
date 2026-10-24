import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "TodoModel.js" as TodoModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // Quick mode is the bare "add a task" prompt (like the reminders flow);
  // the full mode is the tabbed Tasks / Notes window.
  property bool quick: false
  property string tab: "tasks"
  // -1 means the add-task input has focus; otherwise an index into rows.
  property int cursor: -1
  property int editingIndex: -1
  property bool clearConfirmOpen: false

  // Plain Enter files new tasks here; Shift+Enter always files to next.
  property string defaultSection: "backlog"

  property var tasks: []
  readonly property var rows: TodoModel.displayRows(root.tasks)
  // Keeps the cursor on a real row however tasks change (including external edits).
  onRowsChanged: if (root.cursor >= root.rows.length) root.cursor = root.rows.length - 1

  property string dataDir: TodoModel.dataDir(Quickshell.env("XDG_DATA_HOME"), Quickshell.env("HOME"))
  property string todoPath: root.dataDir + "/todo.txt"
  property string notesPath: root.dataDir + "/notes.md"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.xxl
  property int rowHeight: Math.max(Style.space(32), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int doneRowHeight: Math.max(Style.space(24), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: root.quick
    ? root.contentMargin * 2 + input.implicitHeight
    : Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  readonly property string pluginId: (root.manifest && root.manifest.id) || "eh24905.todo"

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dataDir])

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.quick = payload.mode === "quick"
    root.tab = payload.tab === "notes" && !root.quick ? "notes" : "tasks"
    root.cursor = -1
    root.editingIndex = -1
    root.clearConfirmOpen = false
    input.text = ""
    todoFile.reload()
    if (!notesSave.running) notesFile.reload()
    root.opened = true

    Qt.callLater(root.focusCurrent)
  }

  function close() {
    root.flushNotes()
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function focusCurrent() {
    if (root.tab === "notes") notesArea.forceActiveFocus()
    else if (root.cursor < 0) input.forceActiveFocus()
    else listKeys.forceActiveFocus()
  }

  function switchTab(name) {
    if (root.quick) return
    root.tab = name || (root.tab === "tasks" ? "notes" : "tasks")
    Qt.callLater(root.focusCurrent)
  }

  // ---- tasks ----

  function save(nextTasks) {
    root.tasks = nextTasks
    todoFile.setText(TodoModel.serialize(nextTasks))
  }

  function rowOf(taskIndex) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].index === taskIndex) return i
    return -1
  }

  function submit(toNext) {
    var text = input.text.trim()
    if (!text) {
      if (root.quick) root.dismiss()
      return
    }

    var next = root.tasks.slice()
    if (root.editingIndex >= 0 && root.editingIndex < next.length) {
      var edited = TodoModel.fromInput(text)
      if (!edited) return
      next[root.editingIndex] = { section: next[root.editingIndex].section, completed: next[root.editingIndex].completed, text: edited.text }
      var editedIndex = root.editingIndex
      root.editingIndex = -1
      input.text = ""
      root.save(next)
      root.cursor = root.rowOf(editedIndex)
      root.focusCurrent()
      return
    }

    var task = TodoModel.fromInput(text, toNext ? "next" : root.defaultSection)
    if (!task) return
    next.push(task)
    root.save(next)
    input.text = ""
    if (root.quick) root.dismiss()
  }

  // The input sits below the list: moving up from it enters at the last row,
  // and moving down past the last row returns to it.
  function selectRow(delta) {
    var nextCursor = root.cursor < 0 ? root.rows.length - 1 : root.cursor + delta
    root.cursor = nextCursor >= root.rows.length ? -1 : Math.max(nextCursor, 0)
    root.focusCurrent()
  }

  function applyMove(result) {
    root.save(result.tasks)
    root.cursor = Math.max(0, root.rowOf(result.index))
  }

  function moveRowTo(row, section) {
    var r = root.rows[row]
    if (r) root.applyMove(TodoModel.moveTo(root.tasks, r.index, section))
  }

  function toggleDone(row) {
    var r = root.rows[row]
    if (r) root.moveRowTo(row, r.section === "done" ? "next" : "done")
  }

  function reorderRow(row, delta) {
    var r = root.rows[row]
    if (r) root.applyMove(TodoModel.reorder(root.tasks, r.index, delta))
  }

  function deleteRow(row) {
    var r = root.rows[row]
    if (!r) return
    var next = root.tasks.slice()
    next.splice(r.index, 1)
    root.save(next)
    root.cursor = Math.min(row, root.rows.length - 1)
    root.focusCurrent()
  }

  function editRow(row) {
    var r = root.rows[row]
    if (!r) return
    root.editingIndex = r.index
    input.text = r.text
    root.cursor = -1
    root.focusCurrent()
    input.cursorPosition = input.text.length
  }

  function cancelEdit() {
    var row = root.rowOf(root.editingIndex)
    root.editingIndex = -1
    input.text = ""
    root.cursor = row
    root.focusCurrent()
  }

  function requestClearDone() {
    if (TodoModel.count(root.tasks, "done") > 0) root.clearConfirmOpen = true
  }

  function confirmClearDone() {
    root.clearConfirmOpen = false
    root.save(root.tasks.filter(function(t) { return t.section !== "done" }))
    root.focusCurrent()
  }

  function cancelClearDone() {
    root.clearConfirmOpen = false
    root.focusCurrent()
  }

  // ---- notes ----

  function flushNotes() {
    if (!notesSave.running) return
    notesSave.stop()
    notesFile.setText(notesArea.text)
  }

  FileView {
    id: todoFile
    path: root.todoPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.tasks = TodoModel.parse(text())
    onLoadFailed: function(error) { root.tasks = [] }
    onFileChanged: reload()
  }

  // Not watched: reloading under the cursor would fight the editor. Notes
  // are re-read each time the window opens instead.
  FileView {
    id: notesFile
    path: root.notesPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      notesArea.text = text()
      notesSave.stop()
    }
  }

  Timer {
    id: notesSave
    interval: 400
    repeat: false
    onTriggered: notesFile.setText(notesArea.text)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-todo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // Tab switching: keys the focused child doesn't consume bubble up here.
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) return
          var ctrl = event.modifiers & Qt.ControlModifier
          var numbered = event.key === Qt.Key_1 ? "tasks" : event.key === Qt.Key_2 ? "notes" : ""
          if (ctrl && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
            root.switchTab()
            event.accepted = true
          } else if ((ctrl || event.modifiers & Qt.AltModifier) && numbered) {
            root.switchTab(numbered)
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          spacing: root.contentSpacing

          // Tabs
          Row {
            id: tabBar
            visible: !root.quick
            spacing: Style.spacing.xl

            Repeater {
              model: [{ key: "tasks", label: "Tasks" }, { key: "notes", label: "Notes" }]

              delegate: Item {
                required property var modelData
                readonly property bool active: root.tab === modelData.key
                width: tabLabel.implicitWidth
                height: tabLabel.implicitHeight

                Text {
                  id: tabLabel
                  text: parent.modelData.label
                  color: root.foreground
                  opacity: parent.active ? 1 : 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: parent.active ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.switchTab(parent.modelData.key)
                }
              }
            }
          }

          // ---- Tasks tab ----
          Item {
            id: tasksPane
            visible: root.tab === "tasks"
            width: parent.width
            height: root.quick ? input.implicitHeight : parent.height - tabBar.height - root.contentSpacing

            TextField {
              id: input
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: root.quick ? parent.bottom : hints.top
              anchors.bottomMargin: root.quick ? 0 : Style.spacing.lg
              foreground: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              placeholderText: root.editingIndex >= 0
                ? "Edit task…"
                : (root.quick ? "Add a task…   ⇧↵ Next" : "Add a task…")

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.submit(event.modifiers & Qt.ShiftModifier)
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  if (root.editingIndex >= 0) root.cancelEdit()
                  else if (input.text) input.text = ""
                  else root.dismiss()
                  event.accepted = true
                } else if (event.key === Qt.Key_Up && !root.quick && root.editingIndex < 0) {
                  root.selectRow(-1)
                  event.accepted = true
                } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && !(event.modifiers & Qt.ControlModifier)) {
                  root.switchTab("notes")
                  event.accepted = true
                }
              }
            }

            // Keyboard handler for the task list while the cursor is on a row.
            Item {
              id: listKeys
              anchors.fill: list
              z: root.clearConfirmOpen ? 20 : 0

              Keys.onPressed: function(event) {
                if (root.clearConfirmOpen) {
                  if (clearConfirm.handleKey(event)) event.accepted = true
                  return
                }

                var shift = event.modifiers & Qt.ShiftModifier
                var alt = event.modifiers & Qt.AltModifier
                var key = event.key
                var dir = key === Qt.Key_Up || key === Qt.Key_K ? -1 : key === Qt.Key_Down || key === Qt.Key_J ? 1 : 0
                event.accepted = true

                if (dir) {
                  if (alt || shift) root.reorderRow(root.cursor, dir)
                  else root.selectRow(dir)
                } else if (key === Qt.Key_Home) {
                  root.cursor = 0
                } else if (key === Qt.Key_End) {
                  root.cursor = root.rows.length - 1
                } else if (key === Qt.Key_Space || key === Qt.Key_X) {
                  root.toggleDone(root.cursor)
                } else if (key === Qt.Key_N) {
                  root.moveRowTo(root.cursor, "next")
                } else if (key === Qt.Key_B) {
                  root.moveRowTo(root.cursor, "backlog")
                } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_E) {
                  root.editRow(root.cursor)
                } else if (key === Qt.Key_Delete || key === Qt.Key_D) {
                  if (shift) root.requestClearDone()
                  else root.deleteRow(root.cursor)
                } else if (key === Qt.Key_Escape || key === Qt.Key_I || key === Qt.Key_A || key === Qt.Key_Slash) {
                  root.cursor = -1
                  root.focusCurrent()
                } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
                  root.switchTab("notes")
                } else {
                  event.accepted = false
                }
              }

              ConfirmDialog {
                id: clearConfirm
                parent: tasksPane
                anchors.fill: parent
                opened: root.clearConfirmOpen
                z: 30
                message: "Clear all done tasks?"
                confirmText: "Clear"
                background: root.background
                foreground: root.foreground
                scrim: root.scrim
                selectedBackground: root.selectedBackground
                selectedText: root.selectedText
                fontFamily: root.fontFamily
                cornerRadius: root.cornerRadius
                onCanceled: root.cancelClearDone()
                onConfirmed: root.confirmClearDone()
              }
            }

            Flickable {
              id: list
              visible: !root.quick
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: input.top
              anchors.bottomMargin: root.contentSpacing
              contentWidth: width
              contentHeight: sections.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              function ensureVisible(item) {
                var y = item.mapToItem(sections, 0, 0).y
                if (y < list.contentY) list.contentY = y
                else if (y + item.height > list.contentY + list.height) list.contentY = y + item.height - list.height
              }

              Column {
                id: sections
                width: list.width
                spacing: Style.spacing.huge

                Repeater {
                  model: TodoModel.SECTIONS

                  delegate: Column {
                    id: section
                    required property var modelData
                    readonly property string key: modelData.key
                    readonly property var items: root.rows.filter(function(r) { return r.section === section.key })
                    width: sections.width
                    spacing: 0

                    Item {
                      width: parent.width
                      height: sectionLabel.implicitHeight + Style.spacing.md

                      Text {
                        id: sectionLabel
                        x: Style.spacing.rowPaddingX
                        text: section.modelData.label
                        color: root.foreground
                        opacity: section.key === "next" ? 1 : 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.weight: Font.DemiBold
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.spacing.rowPaddingX
                        anchors.baseline: sectionLabel.baseline
                        text: section.items.length
                        color: root.foreground
                        opacity: 0.35
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    Text {
                      visible: section.items.length === 0
                      x: Style.spacing.rowPaddingX
                      topPadding: Style.spacing.xs
                      bottomPadding: Style.spacing.xs
                      text: section.modelData.empty
                      color: root.foreground
                      opacity: 0.35
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.italic: true
                    }

                    Repeater {
                      model: section.items

                      delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property int rowIndex: modelData.row
                        readonly property bool hasCursor: root.cursor === rowIndex
                        readonly property bool done: modelData.section === "done"
                        readonly property bool queued: modelData.section === "next"
                        readonly property bool hovered: rowMouse.containsMouse || actionHover.hovered || markMouse.containsMouse

                        width: section.width
                        height: done ? root.doneRowHeight : root.rowHeight
                        radius: root.cornerRadius
                        color: hasCursor ? root.selectedBackground : (hovered ? Util.alpha(root.foreground, 0.04) : "transparent")

                        onHasCursorChanged: if (hasCursor) list.ensureVisible(row)

                        MouseArea {
                          id: rowMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          onClicked: {
                            root.cursor = row.rowIndex
                            root.focusCurrent()
                          }
                          onDoubleClicked: root.editRow(row.rowIndex)
                        }

                        // The task's todo.txt prefix, set in the margin like a line
                        // number. Clicking it toggles done; hovering previews the "x".
                        Text {
                          id: mark
                          anchors.verticalCenter: parent.verticalCenter
                          leftPadding: Style.spacing.rowPaddingX
                          // Gap before the task text only when a prefix is shown;
                          // empty prefix means the text sits flush at the left padding.
                          rightPadding: text ? Style.spacing.md : 0
                          text: markMouse.containsMouse && !row.done
                            ? "x"
                            : (row.done ? "x " + row.modelData.completed.slice(5) : (row.queued ? "(A)" : ""))
                          color: row.queued || row.hasCursor || markMouse.containsMouse ? root.selectedText : root.foreground
                          opacity: markMouse.containsMouse ? 1 : (row.done ? 0.35 : 0.9)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body

                          MouseArea {
                            id: markMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleDone(row.rowIndex)
                          }
                        }

                        Text {
                          textFormat: Text.PlainText
                          anchors.left: mark.right
                          anchors.right: actions.visible ? actions.left : parent.right
                          anchors.rightMargin: Style.spacing.rowPaddingX
                          anchors.verticalCenter: parent.verticalCenter
                          text: row.modelData.text
                          color: row.hasCursor ? root.selectedText : root.foreground
                          opacity: row.done ? 0.4 : (row.queued || row.hasCursor ? 1 : 0.78)
                          font.family: root.fontFamily
                          font.pixelSize: row.done ? Style.font.body : (row.queued ? Style.font.heading : Style.font.title)
                          font.strikeout: row.done
                          elide: Text.ElideRight
                        }

                        Row {
                          id: actions
                          anchors.right: parent.right
                          anchors.rightMargin: Style.spacing.rowPaddingX
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.spacing.xl
                          visible: row.hasCursor || row.hovered

                          HoverHandler { id: actionHover }

                          Text {
                            visible: !row.done
                            text: row.queued ? "to backlog" : "to next"
                            color: root.foreground
                            opacity: moveMouse.containsMouse ? 1 : 0.5
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption

                            MouseArea {
                              id: moveMouse
                              anchors.fill: parent
                              anchors.margins: -Style.space(4)
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.moveRowTo(row.rowIndex, row.queued ? "backlog" : "next")
                            }
                          }

                          Text {
                            text: "✕"
                            color: deleteMouse.containsMouse ? Color.urgent : root.foreground
                            opacity: deleteMouse.containsMouse ? 1 : 0.5
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption

                            MouseArea {
                              id: deleteMouse
                              anchors.fill: parent
                              anchors.margins: -Style.space(4)
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.deleteRow(row.rowIndex)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Shortcuts for the focused area, drawn as keycaps.
            Flow {
              id: hints
              visible: !root.quick
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              spacing: Style.spacing.xl

              Repeater {
                model: root.cursor < 0
                  ? [["↵", "add to backlog"], ["⇧↵", "add to next"], ["↑", "select"], ["Tab", "notes"], ["Esc", "close"]]
                  : [["Space", "done"], ["n", "next"], ["b", "backlog"], ["⇧↑↓", "reorder"], ["↵", "edit"], ["Del", "delete"], ["⇧Del", "clear done"]]

                delegate: Row {
                  required property var modelData
                  spacing: Style.spacing.sm

                  Rectangle {
                    width: Math.max(height, keyLabel.implicitWidth + Style.spacing.md * 2)
                    height: keyLabel.implicitHeight + Style.spacing.xxs * 2
                    radius: Math.min(root.cornerRadius, Style.space(3))
                    color: "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: Util.alpha(root.foreground, 0.22)

                    Text {
                      id: keyLabel
                      anchors.centerIn: parent
                      text: parent.parent.modelData[0]
                      color: root.foreground
                      opacity: 0.75
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData[1]
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- Notes tab ----
          QQC.ScrollView {
            id: notesPane
            visible: root.tab === "notes"
            width: parent.width
            height: parent.height - tabBar.height - root.contentSpacing

            QQC.TextArea {
              id: notesArea
              wrapMode: TextEdit.Wrap
              color: root.foreground
              selectionColor: Style.selectionFillFor(root.foreground, root.selectedText)
              selectedTextColor: root.foreground
              placeholderText: "Scratch pad…"
              placeholderTextColor: Util.alpha(root.foreground, 0.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              background: null
              padding: 0

              onTextChanged: notesSave.restart()

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.dismiss()
                  event.accepted = true
                }
              }
            }
          }
        }
      }
    }
  }
}
