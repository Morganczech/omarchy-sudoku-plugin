import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "gruut.sudoku"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleGame() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "gruut.sudoku", "{}"])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "9"
    tooltipText: "Sudoku Challenge"
    onPressed: root.toggleGame()
  }
}
