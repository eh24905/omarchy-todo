import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "TodoModel.js" as TodoModel

BarWidget {
  id: root
  moduleName: "eh24905.todo"

  property int nextCount: 0
  property string todoPath: TodoModel.dataDir(Quickshell.env("XDG_DATA_HOME"), Quickshell.env("HOME")) + "/todo.txt"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.todoPath
    watchChanges: true
    printErrors: false
    onLoaded: root.nextCount = TodoModel.count(TodoModel.parse(text()), "next")
    onLoadFailed: function(error) { root.nextCount = 0 }
    onFileChanged: reload()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-tasks, plus the number of tasks in Next.
    text: "" + (root.nextCount > 0 ? " " + root.nextCount : "")
    tooltipText: root.nextCount === 1 ? "1 task in Next" : root.nextCount + " tasks in Next"
    onPressed: function(button) {
      if (!root.bar) return
      var payload = button === Qt.RightButton ? '{"mode":"quick"}' : '{}'
      root.bar.run("omarchy-shell shell toggle eh24905.todo '" + payload + "'")
    }
  }
}
