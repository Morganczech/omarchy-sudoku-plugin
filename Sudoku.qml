import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Sudoku.js" as Sudoku
import "Game.js" as Game
import "Challenge.js" as Challenge
import "Storage.js" as Storage

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool dirReady: false
  property bool storageReady: false
  property bool saveHydrated: false
  property bool statsHydrated: false
  property bool hasSave: false
  property bool dealing: false
  property var saved: null
  property var stats: Storage.emptyStats()
  property var state: Game.blank()
  property var cells: []
  property var digitCounts: [0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var deal: null
  property int menuCursor: 0
  property int difficultyCursor: 0
  property int activeDigit: 0
  property int lockedDigit: 0

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-sudoku"
  readonly property var config: Challenge.defaultConfig()

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

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.flushSave()
    root.opened = false
  }

  function dismiss() {
    root.flushSave()
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "gruut.sudoku")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function maybeReady() {
    if (root.saveHydrated && root.statsHydrated) root.storageReady = true
  }

  function hydrateSave(raw) {
    var parsed = Storage.parse(raw)
    if (parsed !== null) {
      root.saved = parsed
      root.hasSave = true
      if (!root.state || !root.state.mode) {
        var resumed = Game.resume(parsed)
        root.state = resumed
        root.cells = Game.cells(resumed)
        root.digitCounts = Game.digitCounts(resumed)
      }
    } else if (!root.saveHydrated) {
      root.saved = null
      root.hasSave = false
    }
    root.saveHydrated = true
    root.maybeReady()
  }

  function hydrateStats(raw) {
    var parsed = Storage.parseStats(raw)
    if (raw && String(raw).trim()) {
      root.stats = parsed
    } else if (!root.statsHydrated) {
      root.stats = parsed
    }
    root.statsHydrated = true
    root.maybeReady()
  }

  function commit(next, options) {
    var prev = root.state
    var opts = options || {}
    root.state = next
    root.cells = Game.cells(next)
    root.digitCounts = Game.digitCounts(next)
    if (prev && prev.mode && prev.status !== "lost" && next.status === "lost") {
      root.stats = Storage.recordChallengeEnd(
        root.stats,
        next.score || 0,
        next.clearedElapsedMs || 0,
        next.mistakes || 0
      )
      root.flushStats()
      root.clearSave()
      return
    }
    if (prev && prev.mode && prev.status !== "round" && next.status === "round" && next.mode === "challenge") {
      root.stats = Storage.recordChallengeRound(
        root.stats,
        next.score || 0,
        next.clearedElapsedMs || next.elapsedMs || 0,
        next.mistakes || 0
      )
      root.flushStats()
    }
    if (prev && prev.mode && prev.status !== "won" && next.status === "won" && next.mode === "classic") {
      root.stats = Storage.recordClassicWin(root.stats, next.difficulty, next.elapsedMs)
      root.flushStats()
    }
    if (!root.storageReady) return
    if (opts.debounce) root.scheduleSave()
    else root.flushSave()
  }

  function scheduleSave() {
    if (!root.storageReady) return
    saveTimer.restart()
  }

  function flushSave() {
    saveTimer.stop()
    if (!root.storageReady || !root.state) return
    if (root.state.status === "lost") {
      root.clearSave()
      return
    }
    var data = Storage.serialize(root.state)
    if (!data) return
    saveFile.setText(JSON.stringify(data, null, 2) + "\n")
    root.saved = Storage.parse(JSON.stringify(data))
    root.hasSave = root.saved !== null
  }

  function flushStats() {
    if (!root.storageReady) return
    statsFile.setText(JSON.stringify(root.stats, null, 2) + "\n")
  }

  function clearSave() {
    saveTimer.stop()
    root.hasSave = false
    root.saved = null
    if (root.storageReady) saveFile.setText("")
  }

  function canContinue() {
    var state = root.state
    if (state && state.mode && state.status !== "lost" && state.status !== "menu") return true
    return root.hasSave
  }

  function continueGame() {
    var state = root.state
    if (state && state.mode && state.status !== "menu" && state.status !== "lost") {
      root.commit(Game.resume(state))
      keyCatcher.forceActiveFocus()
      return
    }
    if (root.saved) {
      root.commit(Game.resume(root.saved))
      keyCatcher.forceActiveFocus()
    }
  }

  function queueDeal(options) {
    root.lockedDigit = 0
    root.activeDigit = 0
    root.deal = options
    root.dealing = true
    dealTimer.restart()
  }

  function dealNow() {
    var request = root.deal
    root.deal = null
    root.dealing = false
    if (!request) return
    var puzzle = Sudoku.generate(request.difficulty, Date.now())
    root.commit(Game.begin(puzzle, request))
    keyCatcher.forceActiveFocus()
  }

  function startClassic(difficulty) {
    root.queueDeal({
      mode: "classic",
      difficulty: difficulty,
      round: 1,
      hints: root.config.hintsPerPuzzle,
      elapsedMs: 0,
      score: 0
    })
  }

  function startChallenge() {
    root.queueDeal({
      mode: "challenge",
      difficulty: "easy",
      round: 1,
      lives: root.config.startLives,
      hints: root.config.hintsPerPuzzle,
      elapsedMs: 0,
      score: 0
    })
  }

  function nextRound() {
    var state = root.state
    root.queueDeal({
      mode: "challenge",
      difficulty: Challenge.nextDifficulty(state.difficulty),
      round: (state.round || 1) + 1,
      lives: Challenge.livesAfterClear(state.lives, root.config),
      mistakes: state.mistakes || 0,
      hints: root.config.hintsPerPuzzle,
      elapsedMs: state.elapsedMs || 0,
      clearedElapsedMs: state.clearedElapsedMs || state.elapsedMs || 0,
      score: state.score || state.round || 1
    })
  }

  function showMenu() {
    root.menuCursor = 0
    root.lockedDigit = 0
    root.dealing = false
    if (!root.state || !root.state.mode) {
      root.state = Game.blank()
      root.cells = []
      root.digitCounts = [0, 0, 0, 0, 0, 0, 0, 0, 0]
      return
    }
    root.commit(Game.toMenu(root.state))
    keyCatcher.forceActiveFocus()
  }

  function enterDigit(digit) {
    if (!root.state || root.state.screen !== "play" || root.state.paused) return
    if (digit >= 1 && digit <= 9) root.activeDigit = digit
    root.commit(Game.place(root.state, digit))
    keyCatcher.forceActiveFocus()
  }

  function toggleLockDigit(digit) {
    if (root.lockedDigit === digit) {
      root.lockedDigit = 0
    } else {
      root.lockedDigit = digit
      root.activeDigit = digit
    }
    keyCatcher.forceActiveFocus()
  }

  function levelName(difficulty) {
    if (difficulty === "medium") return "Medium"
    if (difficulty === "hard") return "Hard"
    if (difficulty === "expert") return "Expert"
    if (difficulty === "extreme") return "Extreme"
    return "Easy"
  }

  function livesLabel(state) {
    if (!state || state.mode !== "challenge") return String(state ? state.mistakes || 0 : 0)
    var n = state.lives || 0
    if (n > 6) return "♥ ×" + n
    var text = ""
    for (var i = 0; i < n; i++) text += "♥"
    return text || "0"
  }

  function bestTime(difficulty) {
    var table = root.stats && root.stats.classicBestMs ? root.stats.classicBestMs : ({})
    var ms = table[difficulty]
    return ms ? Game.formatTime(ms) : "—"
  }

  function continueSubtitle() {
    var target = (root.state && root.state.mode && root.state.status !== "lost") ? root.state : root.saved
    if (!target || !target.mode) return "Resume saved puzzle"
    if (target.mode === "challenge") {
      return "Survival · Round " + (target.round || 1) + " · " + root.levelName(target.difficulty)
    }
    return "Classic · " + root.levelName(target.difficulty)
  }

  function activateMenu() {
    var labels = menuModel()
    var item = labels[root.menuCursor]
    if (!item) return
    if (item.id === "continue") root.continueGame()
    else if (item.id === "classic") {
      root.difficultyCursor = 0
      root.state = Object.assign({}, root.state, { screen: "difficulty" })
    } else if (item.id === "challenge") root.startChallenge()
    else if (item.id === "stats") root.state = Object.assign({}, root.state, { screen: "stats" })
    else if (item.id === "quit") root.dismiss()
  }

  function activateDifficulty() {
    if (root.difficultyCursor === 0) root.startClassic("easy")
    else if (root.difficultyCursor === 1) root.startClassic("medium")
    else if (root.difficultyCursor === 2) root.startClassic("hard")
    else root.showMenu()
  }

  function menuModel() {
    var items = []
    if (root.canContinue()) items.push({ id: "continue", label: "Continue", sub: root.continueSubtitle() })
    items.push({ id: "classic", label: "Classic", sub: "Easy · Medium · Hard" })
    items.push({ id: "challenge", label: "Survival Challenge", sub: "3 lives · progressive difficulty" })
    items.push({ id: "stats", label: "Statistics", sub: "Best times & survival records" })
    items.push({ id: "quit", label: "Quit", sub: "Save and close overlay" })
    return items
  }

  function handleKey(event) {
    var screen = root.dealing ? "dealing" : (root.state ? root.state.screen : "menu")
    var text = event.text || ""
    var lower = text.toLowerCase()
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0

    if (screen === "dealing") {
      event.accepted = true
      return
    }

    if (screen === "menu") {
      var count = root.menuModel().length
      if (event.key === Qt.Key_Escape || lower === "q") root.dismiss()
      else if (event.key === Qt.Key_Down || lower === "j") root.menuCursor = Math.min(count - 1, root.menuCursor + 1)
      else if (event.key === Qt.Key_Up || lower === "k") root.menuCursor = Math.max(0, root.menuCursor - 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.activateMenu()
      else return
      event.accepted = true
      return
    }

    if (screen === "difficulty") {
      if (event.key === Qt.Key_Escape) root.showMenu()
      else if (event.key === Qt.Key_Down || lower === "j") root.difficultyCursor = Math.min(3, root.difficultyCursor + 1)
      else if (event.key === Qt.Key_Up || lower === "k") root.difficultyCursor = Math.max(0, root.difficultyCursor - 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.activateDifficulty()
      else return
      event.accepted = true
      return
    }

    if (screen === "stats") {
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || lower === "q")
        root.showMenu()
      else return
      event.accepted = true
      return
    }

    if (screen === "round") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.nextRound()
      else if (event.key === Qt.Key_Escape) root.showMenu()
      else return
      event.accepted = true
      return
    }

    if (screen === "won" || screen === "lost") {
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || lower === "q")
        root.showMenu()
      else return
      event.accepted = true
      return
    }

    if (screen !== "play") return

    if (root.state.paused) {
      if (lower === "p" || event.key === Qt.Key_Space || event.key === Qt.Key_Return) root.commit(Game.togglePause(root.state))
      else if (event.key === Qt.Key_Escape) root.showMenu()
      else if (lower === "q") root.dismiss()
      else return
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (root.lockedDigit > 0) root.lockedDigit = 0
      else root.showMenu()
    }
    else if (lower === "q") root.dismiss()
    else if (event.key === Qt.Key_Left || lower === "h") root.commit(Game.move(root.state, 0, -1), { debounce: true })
    else if (event.key === Qt.Key_Right || lower === "l") root.commit(Game.move(root.state, 0, 1), { debounce: true })
    else if (event.key === Qt.Key_Up || lower === "k") root.commit(Game.move(root.state, -1, 0), { debounce: true })
    else if (event.key === Qt.Key_Down || lower === "j") root.commit(Game.move(root.state, 1, 0), { debounce: true })
    else if (lower === "n") root.commit(Game.toggleNotes(root.state))
    else if (lower === "u" && !ctrl) root.commit(Game.undo(root.state))
    else if ((ctrl && (event.key === Qt.Key_R || event.key === Qt.Key_Y)) || lower === "r") root.commit(Game.redo(root.state))
    else if (text === "?" || (event.key === Qt.Key_Slash && (event.modifiers & Qt.ShiftModifier))) root.commit(Game.hint(root.state))
    else if (lower === "p") root.commit(Game.togglePause(root.state))
    else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete || event.key === Qt.Key_0 || event.key === Qt.Key_Keypad0 || lower === "x" || lower === "e")
      root.enterDigit(0)
    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
      root.enterDigit(event.key - Qt.Key_0)
    else if (event.key >= Qt.Key_Keypad1 && event.key <= Qt.Key_Keypad9)
      root.enterDigit(event.key - Qt.Key_Keypad0)
    else return
    event.accepted = true
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.dataDir]
    running: false
    onExited: {
      root.dirReady = true
    }
  }

  FileView {
    id: saveFile
    path: root.dirReady ? root.dataDir + "/save.json" : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.hydrateSave(saveFile.text())
    onLoadFailed: root.hydrateSave("")
  }

  FileView {
    id: statsFile
    path: root.dirReady ? root.dataDir + "/stats.json" : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.hydrateStats(statsFile.text())
    onLoadFailed: root.hydrateStats("")
  }

  Timer {
    id: saveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushSave()
  }

  Timer {
    id: dealTimer
    interval: 16
    repeat: false
    onTriggered: root.dealNow()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && !root.dealing && root.state.status === "playing" && !root.state.paused && root.state.screen === "play"
    onTriggered: root.commit(Game.tick(root.state, 1000), { debounce: true })
  }

  Component.onCompleted: mkdirProc.running = true
  Component.onDestruction: {
    root.flushSave()
    root.flushStats()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "gruut-sudoku"
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
      width: Math.min(Style.space(580), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(780), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) { root.handleKey(event) }
      }

      Column {
        id: mainColumn
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // Top Header Bar with Title, Mode Pill, and Mouse Controls
        Item {
          id: headerBar
          width: parent.width
          height: Style.space(34)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Sudoku"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Rectangle {
              visible: root.storageReady && !root.dealing && root.state.screen === "play"
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(22)
              width: modeBadgeText.implicitWidth + Style.space(16)
              radius: Style.cornerRadius > 0 ? Math.max(2, Style.cornerRadius) : 0
              color: Util.alpha(Color.accent, 0.14)
              border.width: 1
              border.color: Util.alpha(Color.accent, 0.45)

              Text {
                id: modeBadgeText
                anchors.centerIn: parent
                text: (root.state.mode === "challenge" ? "SURVIVAL" : "CLASSIC")
                      + " · " + root.levelName(root.state.difficulty).toUpperCase()
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Rectangle {
              visible: root.storageReady && !root.dealing && root.state.screen === "play" && root.lockedDigit > 0
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(22)
              width: lockBadgeText.implicitWidth + Style.space(14)
              radius: Style.cornerRadius > 0 ? Math.max(2, Style.cornerRadius) : 0
              color: Util.alpha(Color.accent, 0.22)
              border.width: 1
              border.color: Color.accent

              Text {
                id: lockBadgeText
                anchors.centerIn: parent
                text: "BRUSH: " + root.lockedDigit
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.lockedDigit = 0
                  keyCatcher.forceActiveFocus()
                }
              }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            HeaderActionButton {
              visible: root.storageReady && !root.dealing && root.state.screen === "play"
              label: root.state.paused ? "▶ Resume" : "⏸ Pause"
              shortcutHint: "P"
              activeState: root.state.paused
              onClicked: {
                root.commit(Game.togglePause(root.state))
                keyCatcher.forceActiveFocus()
              }
            }

            HeaderActionButton {
              visible: root.storageReady && !root.dealing && root.state.screen !== "menu"
              label: "☰ Menu"
              shortcutHint: "Esc"
              onClicked: root.showMenu()
            }

            HeaderActionButton {
              label: "✕"
              shortcutHint: ""
              onClicked: root.dismiss()
            }
          }
        }

        // Main Content Area
        Item {
          id: bodyArea
          width: parent.width
          height: parent.height - headerBar.height - footerText.height - Style.spacing.md * 2

          // Loading State
          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.sm
            visible: !root.storageReady

            Text {
              text: "Loading saved game..."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          // Main Menu Screen
          Column {
            id: menuColumn
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(320))
            spacing: Style.spacing.sm
            visible: root.storageReady && !root.dealing && root.state.screen === "menu"

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "SUDOKU CHALLENGE"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Classic puzzles & progressive survival mode"
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Item { width: 1; height: Style.spacing.xs }

            Repeater {
              model: root.menuModel()
              delegate: MenuRow {
                required property var modelData
                required property int index
                width: menuColumn.width
                label: modelData.label
                sublabel: modelData.sub || ""
                chosen: index === root.menuCursor
                onHovered: root.menuCursor = index
                onClicked: {
                  root.menuCursor = index
                  root.activateMenu()
                  keyCatcher.forceActiveFocus()
                }
              }
            }
          }

          // Difficulty Selection Screen
          Column {
            id: difficultyColumn
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(320))
            spacing: Style.spacing.sm
            visible: root.storageReady && !root.dealing && root.state.screen === "difficulty"

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "SELECT DIFFICULTY"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Classic Mode · Unique Solution Guaranteed"
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Item { width: 1; height: Style.spacing.xs }

            MenuRow {
              width: difficultyColumn.width
              label: "Easy"
              sublabel: "36–40 givens · singles only"
              chosen: root.difficultyCursor === 0
              onHovered: root.difficultyCursor = 0
              onClicked: { root.difficultyCursor = 0; root.activateDifficulty() }
            }
            MenuRow {
              width: difficultyColumn.width
              label: "Medium"
              sublabel: "30–35 givens · pairs & singles"
              chosen: root.difficultyCursor === 1
              onHovered: root.difficultyCursor = 1
              onClicked: { root.difficultyCursor = 1; root.activateDifficulty() }
            }
            MenuRow {
              width: difficultyColumn.width
              label: "Hard"
              sublabel: "25–29 givens · advanced deductions"
              chosen: root.difficultyCursor === 2
              onHovered: root.difficultyCursor = 2
              onClicked: { root.difficultyCursor = 2; root.activateDifficulty() }
            }
            MenuRow {
              width: difficultyColumn.width
              label: "← Back to Menu"
              sublabel: ""
              chosen: root.difficultyCursor === 3
              onHovered: root.difficultyCursor = 3
              onClicked: { root.difficultyCursor = 3; root.activateDifficulty() }
            }
          }

          // Statistics Screen
          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(360))
            spacing: Style.spacing.md
            visible: root.storageReady && !root.dealing && root.state.screen === "stats"

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "STATISTICS"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs

              StatRecordRow { label: "Classic Wins"; value: String(root.stats.classicWins || 0) }
              StatRecordRow { label: "Best Time · Easy"; value: root.bestTime("easy") }
              StatRecordRow { label: "Best Time · Medium"; value: root.bestTime("medium") }
              StatRecordRow { label: "Best Time · Hard"; value: root.bestTime("hard") }
              StatRecordRow { label: "Survival Best Streak"; value: String(root.stats.challengeBestRound || 0) + " rounds"; accentValue: true }
              StatRecordRow { label: "Survival Best Time"; value: root.stats.challengeBestTimeMs ? Game.formatTime(root.stats.challengeBestTimeMs) : "—" }
              StatRecordRow { label: "Survival Mistakes (Best / All)"; value: String(root.stats.challengeBestMistakes || 0) + " / " + String(root.stats.challengeTotalMistakes || 0) }
              StatRecordRow { label: "Survival Runs Played"; value: String(root.stats.challengeRuns || 0) }
            }

            MenuRow {
              width: parent.width
              label: "← Back to Menu"
              chosen: true
              onClicked: root.showMenu()
            }
          }

          // Round / Won / Lost / Dealing Screen
          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.md
            width: Math.min(parent.width, Style.space(340))
            visible: root.storageReady && (root.dealing || root.state.screen === "round" || root.state.screen === "won" || root.state.screen === "lost")

            Rectangle {
              width: parent.width
              height: summaryCol.implicitHeight + Style.space(32)
              radius: Style.cornerRadius
              color: Style.normalFill
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.16)

              Column {
                id: summaryCol
                anchors.centerIn: parent
                width: parent.width - Style.space(28)
                spacing: Style.spacing.sm

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.dealing ? "Generating Puzzle..."
                      : root.state.screen === "lost" ? "GAME OVER"
                      : root.state.screen === "won" ? "PUZZLE COMPLETE"
                      : "ROUND CLEAR"
                  color: root.dealing ? root.foreground
                       : root.state.screen === "lost" ? Color.urgent
                       : Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  visible: !root.dealing
                  text: root.state.screen === "lost"
                        ? ("Rounds cleared: " + (root.state.score || 0)
                           + "\nCleared survival time: " + Game.formatTime(root.state.clearedElapsedMs || 0)
                           + "\nTotal time: " + Game.formatTime(root.state.elapsedMs)
                           + "  ·  Mistakes (lives lost): " + (root.state.mistakes || 0))
                        : root.state.screen === "won"
                        ? ("Difficulty: " + root.levelName(root.state.difficulty) + "\nTime: " + Game.formatTime(root.state.elapsedMs) + "  ·  Mistakes: " + (root.state.mistakes || 0))
                        : root.state.screen === "round"
                        ? ("Rounds cleared: " + (root.state.score || root.state.round || 1)
                           + "  ·  Survival time: " + Game.formatTime(root.state.clearedElapsedMs || root.state.elapsedMs)
                           + "\nMistakes so far: " + (root.state.mistakes || 0)
                           + "  ·  Lives: " + (root.state.lives || 0) + " + " + root.config.bonusLives + " bonus"
                           + "\nNext difficulty: " + root.levelName(Challenge.nextDifficulty(root.state.difficulty)))
                        : ""
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            MenuRow {
              visible: !root.dealing && root.state.screen === "round"
              width: parent.width
              label: "Next Round →"
              sublabel: "Press Enter or click to continue"
              chosen: true
              onClicked: root.nextRound()
            }

            MenuRow {
              visible: !root.dealing && (root.state.screen === "won" || root.state.screen === "lost")
              width: parent.width
              label: root.state.mode === "challenge" ? "New Survival Run" : "Play Again (" + root.levelName(root.state.difficulty) + ")"
              chosen: true
              onClicked: {
                if (root.state.mode === "challenge") root.startChallenge()
                else root.startClassic(root.state.difficulty || "easy")
              }
            }

            MenuRow {
              visible: !root.dealing
              width: parent.width
              label: "Main Menu"
              chosen: false
              onClicked: root.showMenu()
            }
          }

          // Active Play Screen
          Column {
            id: playColumn
            anchors.fill: parent
            spacing: Style.spacing.sm
            visible: root.storageReady && !root.dealing && root.state.screen === "play"

            // Telemetry Stat Chips
            Row {
              id: statsRow
              width: parent.width
              spacing: Style.spacing.sm

              StatChip { title: "TIME"; value: Game.formatTime(root.state.elapsedMs) }
              StatChip {
                title: root.state.mode === "challenge" ? "LIVES" : "MISTAKES"
                value: root.livesLabel(root.state)
                valueColor: root.state.mode === "challenge"
                            ? Color.urgent
                            : (root.state.mistakes > 0 ? Color.urgent : root.foreground)
              }
              StatChip {
                title: "ROUND"
                value: root.state.mode === "challenge" ? String(root.state.round || 1) : "—"
              }
              StatChip { title: "LEVEL"; value: root.levelName(root.state.difficulty) }
              StatChip {
                title: "HINTS"
                value: String(root.state.hintsLeft || 0)
                valueColor: (root.state.hintsLeft || 0) > 0 ? Color.accent : root.foreground
              }
            }

            // 9x9 Sudoku Board Host
            Item {
              id: boardHost
              width: parent.width
              height: Math.max(Style.space(220), parent.height - statsRow.height - actionToolbar.height - numpadRow.height - Style.spacing.sm * 3)

              Rectangle {
                id: boardGrid
                anchors.centerIn: parent

                readonly property int outerBorder: Math.max(2, Style.space(2))
                readonly property int hairline: 1
                readonly property int blockGap: Math.max(2, Style.space(2))
                readonly property int totalGaps: outerBorder * 2 + hairline * 6 + blockGap * 2
                property int cellSize: Math.max(26, Math.min(48, Math.floor((Math.min(boardHost.width, boardHost.height) - totalGaps - 4) / 9)))
                readonly property int blockSize: cellSize * 3 + hairline * 2

                function origin(index) {
                  var blocks = Math.floor(index / 3)
                  return outerBorder + index * (cellSize + hairline) + blocks * (blockGap - hairline)
                }

                width: outerBorder * 2 + blockSize * 3 + blockGap * 2
                height: width
                radius: 0

                // Outer frame & 3x3 block separator plate (medium-contrast theme border)
                color: Qt.tint(root.background, Util.alpha(root.foreground, 0.50))

                // 9 sub-block plates providing subtle 1px hairlines between individual cells
                Repeater {
                  model: 9
                  delegate: Rectangle {
                    required property int index
                    readonly property int bRow: Math.floor(index / 3)
                    readonly property int bCol: index % 3
                    x: boardGrid.outerBorder + bCol * (boardGrid.blockSize + boardGrid.blockGap)
                    y: boardGrid.outerBorder + bRow * (boardGrid.blockSize + boardGrid.blockGap)
                    width: boardGrid.blockSize
                    height: boardGrid.blockSize
                    color: Qt.tint(root.background, Util.alpha(root.foreground, 0.18))
                    z: 1
                  }
                }

                // 81 Cells
                Repeater {
                  model: 81
                  delegate: Rectangle {
                    id: cellItem
                    required property int index
                    readonly property int row: Math.floor(index / 9)
                    readonly property int col: index % 9
                    readonly property var cell: root.cells.length === 81 ? root.cells[index] : null
                    readonly property bool isHovered: cellMouse.containsMouse

                    x: boardGrid.origin(col)
                    y: boardGrid.origin(row)
                    width: boardGrid.cellSize
                    height: boardGrid.cellSize
                    z: cell && cell.selected ? 4 : 2

                    color: {
                      if (!cell) return root.background
                      if (cell.selected) return Qt.tint(root.background, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.32))
                      if (cell.wrong) return Qt.tint(root.background, Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.20))
                      if (cell.same) return Qt.tint(root.background, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18))
                      if (isHovered) return Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13))
                      if (cell.peer) return Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07))
                      return root.background
                    }

                    border.width: {
                      if (!cell) return 0
                      if (cell.selected) return 2
                      if (cell.wrong || cell.same) return 1
                      return 0
                    }
                    border.color: {
                      if (!cell) return "transparent"
                      if (cell.wrong && !cell.selected) return Color.urgent
                      if (cell.same && !cell.selected) return Util.alpha(Color.accent, 0.55)
                      return Color.accent
                    }

                    // Placed or Given Digit
                    Text {
                      anchors.centerIn: parent
                      visible: cellItem.cell && cellItem.cell.value > 0 && !root.state.paused
                      text: cellItem.cell && cellItem.cell.value ? String(cellItem.cell.value) : ""
                      color: !cellItem.cell
                             ? root.foreground
                             : cellItem.cell.wrong
                               ? Color.urgent
                               : cellItem.cell.given
                                 ? root.foreground
                                 : Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(15, Math.round(boardGrid.cellSize * 0.54))
                      font.bold: true
                    }

                    // 3x3 Subgrid for Pencil Notes
                    Item {
                      anchors.fill: parent
                      anchors.margins: 2
                      visible: cellItem.cell && cellItem.cell.hasNotes && !root.state.paused

                      Grid {
                        id: notesGrid
                        anchors.fill: parent
                        columns: 3
                        rows: 3
                        spacing: 0

                        Repeater {
                          model: 9
                          delegate: Item {
                            id: noteSlot
                            required property int index
                            width: notesGrid.width / 3
                            height: notesGrid.height / 3
                            readonly property bool hasBit: cellItem.cell && cellItem.cell.noteBits ? cellItem.cell.noteBits[index] : false

                            Text {
                              anchors.centerIn: parent
                              visible: noteSlot.hasBit
                              text: String(noteSlot.index + 1)
                              color: Color.accent
                              opacity: 0.9
                              font.family: root.fontFamily
                              font.pixelSize: Math.max(8, Math.floor(boardGrid.cellSize * 0.24))
                              font.bold: true
                            }
                          }
                        }
                      }
                    }

                    MouseArea {
                      id: cellMouse
                      anchors.fill: parent
                      enabled: !root.state.paused
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      onClicked: function (mouse) {
                        var nextState = Game.select(root.state, cellItem.index)
                        if (mouse.button === Qt.RightButton) {
                          nextState = Game.place(nextState, 0)
                        } else if (root.lockedDigit >= 1 && root.lockedDigit <= 9) {
                          nextState = Game.place(nextState, root.lockedDigit)
                        }
                        root.commit(nextState)
                        if (cellItem.cell && cellItem.cell.value > 0 && root.lockedDigit === 0) {
                          root.activeDigit = cellItem.cell.value
                        }
                        keyCatcher.forceActiveFocus()
                      }
                    }
                  }
                }

                // Pause Overlay inside Board Frame
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: boardGrid.outerBorder
                  visible: root.state.paused
                  color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.95)
                  z: 10

                  Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.75, Style.space(220))
                    spacing: Style.spacing.sm

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: "GAME PAUSED"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                    }

                    Item { width: 1; height: Style.spacing.xs }

                    MenuRow {
                      width: parent.width
                      label: "▶ Resume"
                      sublabel: "Shortcut: P"
                      chosen: true
                      onClicked: {
                        root.commit(Game.togglePause(root.state))
                        keyCatcher.forceActiveFocus()
                      }
                    }

                    MenuRow {
                      width: parent.width
                      label: "☰ Main Menu"
                      sublabel: "Shortcut: Esc"
                      chosen: false
                      onClicked: root.showMenu()
                    }
                  }
                }
              }
            }

            // Interactive Action Toolbar (Undo, Redo, Erase, Notes, Hint)
            Row {
              id: actionToolbar
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Math.max(boardGrid.width, Style.space(380)))
              height: Style.space(44)
              spacing: Style.spacing.xs

              ActionPillButton {
                width: (parent.width - Style.spacing.xs * 4) / 5
                height: parent.height
                iconGlyph: "↶"
                label: "Undo"
                badge: "U"
                enabledState: !root.state.paused && root.state.history && root.state.history.length > 0
                onClicked: {
                  root.commit(Game.undo(root.state))
                  keyCatcher.forceActiveFocus()
                }
              }

              ActionPillButton {
                width: (parent.width - Style.spacing.xs * 4) / 5
                height: parent.height
                iconGlyph: "↷"
                label: "Redo"
                badge: "R"
                enabledState: !root.state.paused && root.state.future && root.state.future.length > 0
                onClicked: {
                  root.commit(Game.redo(root.state))
                  keyCatcher.forceActiveFocus()
                }
              }

              ActionPillButton {
                width: (parent.width - Style.spacing.xs * 4) / 5
                height: parent.height
                iconGlyph: "⌫"
                label: "Erase"
                badge: "0"
                enabledState: !root.state.paused
                urgentAccent: true
                onClicked: root.enterDigit(0)
              }

              ActionPillButton {
                width: (parent.width - Style.spacing.xs * 4) / 5
                height: parent.height
                iconGlyph: "✎"
                label: root.state.notesMode ? "Notes ON" : "Notes"
                badge: "N"
                activeState: root.state.notesMode === true
                enabledState: !root.state.paused
                onClicked: {
                  root.commit(Game.toggleNotes(root.state))
                  keyCatcher.forceActiveFocus()
                }
              }

              ActionPillButton {
                width: (parent.width - Style.spacing.xs * 4) / 5
                height: parent.height
                iconGlyph: "★"
                label: "Hint (" + (root.state.hintsLeft || 0) + ")"
                badge: "?"
                enabledState: !root.state.paused && (root.state.hintsLeft || 0) > 0
                onClicked: {
                  root.commit(Game.hint(root.state))
                  keyCatcher.forceActiveFocus()
                }
              }
            }

            // Interactive 1–9 Numpad with Remaining Counts
            Row {
              id: numpadRow
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Math.max(boardGrid.width, Style.space(380)))
              height: Style.space(50)
              spacing: Style.spacing.xs

              Repeater {
                model: 9
                delegate: Rectangle {
                  id: numKey
                  required property int index
                  readonly property int digit: index + 1
                  readonly property int placedCount: root.digitCounts && root.digitCounts.length === 9 ? root.digitCounts[index] : 0
                  readonly property int remaining: Math.max(0, 9 - placedCount)
                  readonly property bool completed: remaining === 0
                  readonly property bool isLocked: root.lockedDigit === digit
                  readonly property bool isActive: root.activeDigit === digit || isLocked

                  width: (numpadRow.width - Style.spacing.xs * 8) / 9
                  height: numpadRow.height
                  radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius) : 0
                  opacity: completed && !isLocked ? 0.42 : 1.0

                  color: {
                    if (numMouse.pressed) return Util.alpha(Color.accent, 0.35)
                    if (isLocked) return Util.alpha(Color.accent, 0.26)
                    if (numMouse.containsMouse) return Util.alpha(root.foreground, 0.14)
                    if (isActive) return Util.alpha(Color.accent, 0.14)
                    return Style.normalFill
                  }

                  border.width: isLocked ? 2 : 1
                  border.color: {
                    if (isLocked || isActive) return Color.accent
                    if (numMouse.containsMouse) return Util.alpha(root.foreground, 0.38)
                    return Util.alpha(root.foreground, 0.14)
                  }

                  Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: String(numKey.digit)
                      color: numKey.isLocked || numKey.isActive ? Color.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: numKey.completed ? "✓" : String(numKey.remaining)
                      color: numKey.completed ? Color.accent : root.foreground
                      opacity: numKey.completed ? 0.9 : 0.55
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(9, Style.font.caption - 1)
                    }
                  }

                  MouseArea {
                    id: numMouse
                    anchors.fill: parent
                    enabled: !root.state.paused
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (mouse) {
                      if (mouse.button === Qt.RightButton) {
                        root.toggleLockDigit(numKey.digit)
                      } else {
                        root.enterDigit(numKey.digit)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // Compact Footer Hint Bar
        Text {
          id: footerText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: root.state.screen === "play"
                ? "Click / 1–9 place · Right-click cell erases · Right-click 1–9 locks brush · hjkl move"
                : "Mouse or arrows navigate · Enter selects · Esc closes"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Math.max(9, Style.font.caption - 1)
        }
      }
    }
  }

  component HeaderActionButton: Rectangle {
    id: hdrBtn
    property string label: ""
    property string shortcutHint: ""
    property bool activeState: false
    signal clicked()

    height: Style.space(26)
    width: hdrBtnRow.implicitWidth + Style.space(16)
    radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius) : 0
    color: hdrMouse.pressed
           ? Util.alpha(Color.accent, 0.28)
           : hdrBtn.activeState
             ? Util.alpha(Color.accent, 0.18)
             : hdrMouse.containsMouse
               ? Util.alpha(root.foreground, 0.12)
               : Style.normalFill
    border.width: 1
    border.color: hdrBtn.activeState
                  ? Color.accent
                  : hdrMouse.containsMouse
                    ? Util.alpha(root.foreground, 0.35)
                    : Util.alpha(root.foreground, 0.14)

    Row {
      id: hdrBtnRow
      anchors.centerIn: parent
      spacing: Style.spacing.xs

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: hdrBtn.label
        color: hdrBtn.activeState ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: hdrBtn.activeState
      }

      Text {
        visible: hdrBtn.shortcutHint !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: "[" + hdrBtn.shortcutHint + "]"
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: hdrMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: hdrBtn.clicked()
    }
  }

  component ActionPillButton: Rectangle {
    id: pill
    property string iconGlyph: ""
    property string label: ""
    property string badge: ""
    property bool activeState: false
    property bool enabledState: true
    property bool urgentAccent: false
    signal clicked()

    radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius) : 0
    opacity: pill.enabledState ? 1.0 : 0.4
    color: {
      if (!pill.enabledState) return Style.normalFill
      if (pillMouse.pressed) return Util.alpha(Color.accent, 0.30)
      if (pill.activeState) return Util.alpha(Color.accent, 0.20)
      if (pillMouse.containsMouse) return Util.alpha(root.foreground, 0.13)
      return Style.normalFill
    }
    border.width: pill.activeState ? 2 : 1
    border.color: {
      if (pill.activeState) return Color.accent
      if (pill.enabledState && pillMouse.containsMouse) return Util.alpha(root.foreground, 0.38)
      return Util.alpha(root.foreground, 0.14)
    }

    Column {
      anchors.centerIn: parent
      spacing: 1

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.xxs

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: pill.iconGlyph
          color: pill.urgentAccent ? Color.urgent : (pill.activeState ? Color.accent : root.foreground)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          visible: pill.badge !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: pill.badge
          color: pill.activeState ? Color.accent : root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Math.max(9, Style.font.caption - 1)
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: pill.label
        color: pill.activeState ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: pill.activeState
      }
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      enabled: pill.enabledState
      hoverEnabled: true
      cursorShape: pill.enabledState ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: pill.clicked()
    }
  }

  component MenuRow: Rectangle {
    id: row
    property string label: ""
    property string sublabel: ""
    property bool chosen: false
    signal clicked()
    signal hovered()

    height: row.sublabel !== "" ? Style.space(48) : Style.space(38)
    radius: Style.cornerRadius
    color: rowMouse.pressed
           ? Util.alpha(Color.accent, 0.28)
           : chosen
             ? root.selectedBackground
             : rowMouse.containsMouse
               ? Util.alpha(root.foreground, 0.08)
               : Style.normalFill
    border.width: 1
    border.color: chosen ? root.selectedText : Util.alpha(root.border, 0.55)

    Column {
      anchors.centerIn: parent
      spacing: 1

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: row.label
        color: chosen ? root.selectedText : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: chosen
      }

      Text {
        visible: row.sublabel !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: row.sublabel
        color: chosen ? root.selectedText : root.foreground
        opacity: 0.65
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: row.hovered()
      onClicked: row.clicked()
    }
  }

  component StatRecordRow: Rectangle {
    id: statRecRow
    property string label: ""
    property string value: ""
    property bool accentValue: false

    width: parent.width
    height: Style.space(34)
    radius: Style.cornerRadius
    color: Style.normalFill
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.12)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: statRecRow.label
      color: root.foreground
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: statRecRow.value
      color: statRecRow.accentValue ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  component StatChip: Rectangle {
    id: statChip
    property string title: ""
    property string value: ""
    property color valueColor: root.foreground

    width: (parent.width - Style.spacing.sm * 4) / 5
    height: Style.space(44)
    radius: Style.cornerRadius
    color: Style.normalFill
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.12)

    Column {
      anchors.centerIn: parent
      spacing: 1
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: statChip.title
        color: root.foreground
        opacity: 0.62
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: statChip.value
        color: statChip.valueColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
  }
}
