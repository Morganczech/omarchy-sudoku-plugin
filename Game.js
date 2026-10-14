// Play state. Boards are copied on every change so the QML UI sees a new object.

function zeros(n) {
  var out = []
  for (var i = 0; i < n; i++) out.push(0)
  return out
}

function blank() {
  return {
    screen: "menu",
    mode: "",
    difficulty: "",
    round: 0,
    lives: -1,
    mistakes: 0,
    hintsLeft: 0,
    notesMode: false,
    paused: false,
    elapsedMs: 0,
    clearedElapsedMs: 0,
    board: zeros(81),
    given: [],
    solution: zeros(81),
    notes: zeros(81),
    selected: 0,
    status: "menu",
    score: 0,
    history: [],
    future: [],
    message: ""
  }
}

function cloneShallow(state) {
  return {
    screen: state.screen,
    mode: state.mode,
    difficulty: state.difficulty,
    round: state.round,
    lives: state.lives,
    mistakes: state.mistakes,
    hintsLeft: state.hintsLeft,
    notesMode: state.notesMode,
    paused: state.paused,
    elapsedMs: state.elapsedMs,
    clearedElapsedMs: state.clearedElapsedMs || 0,
    board: state.board.slice(),
    given: state.given.slice(),
    solution: state.solution.slice(),
    notes: state.notes.slice(),
    selected: state.selected,
    status: state.status,
    score: state.score,
    history: state.history,
    future: state.future,
    message: state.message || ""
  }
}

function snapshot(state) {
  return {
    board: state.board.slice(),
    notes: state.notes.slice(),
    lives: state.lives,
    mistakes: state.mistakes,
    hintsLeft: state.hintsLeft,
    selected: state.selected
  }
}

function restore(state, snap) {
  var next = cloneShallow(state)
  next.board = snap.board.slice()
  next.notes = snap.notes.slice()
  next.lives = snap.lives
  next.mistakes = snap.mistakes
  next.hintsLeft = snap.hintsLeft
  next.selected = snap.selected
  next.history = state.history
  next.future = state.future
  return next
}

function withHistory(state) {
  var next = cloneShallow(state)
  var past = state.history.slice()
  past.push(snapshot(state))
  if (past.length > 200) past.shift()
  next.history = past
  next.future = []
  return next
}

function givenFrom(board) {
  var given = []
  for (var i = 0; i < 81; i++) given.push(board[i] !== 0)
  return given
}

function begin(puzzle, options) {
  var settings = options || {}
  var board = puzzle.board.slice()
  return {
    screen: "play",
    mode: settings.mode || "classic",
    difficulty: settings.difficulty || "easy",
    round: settings.round || 1,
    lives: settings.mode === "challenge" ? settings.lives : -1,
    mistakes: settings.mistakes || 0,
    hintsLeft: settings.hints == null ? 3 : settings.hints,
    notesMode: false,
    paused: false,
    elapsedMs: settings.elapsedMs || 0,
    clearedElapsedMs: settings.clearedElapsedMs || 0,
    board: board,
    given: givenFrom(board),
    solution: puzzle.solution.slice(),
    notes: zeros(81),
    selected: firstEmpty(board),
    status: "playing",
    score: settings.score || 0,
    history: [],
    future: [],
    message: ""
  }
}

function firstEmpty(board) {
  for (var i = 0; i < 81; i++) if (board[i] === 0) return i
  return 0
}

function toMenu(state) {
  var next = cloneShallow(state)
  next.screen = "menu"
  next.paused = false
  next.message = ""
  return next
}

function resume(state) {
  if (!state || !state.mode) return state
  var next = cloneShallow(state)
  next.paused = false
  if (next.status === "won") next.screen = "won"
  else if (next.status === "round") next.screen = "round"
  else if (next.status === "lost") next.screen = "lost"
  else {
    next.status = "playing"
    next.screen = "play"
  }
  return next
}

function move(state, deltaRow, deltaCol) {
  if (!state || state.screen !== "play" || state.paused) return state
  var row = Math.floor(state.selected / 9) + deltaRow
  var col = (state.selected % 9) + deltaCol
  if (row < 0) row = 0
  if (row > 8) row = 8
  if (col < 0) col = 0
  if (col > 8) col = 8
  var next = cloneShallow(state)
  next.selected = row * 9 + col
  return next
}

function select(state, index) {
  if (!state || state.screen !== "play" || state.paused) return state
  if (index < 0 || index > 80) return state
  var next = cloneShallow(state)
  next.selected = index
  return next
}

function toggleNotes(state) {
  if (!state || state.screen !== "play") return state
  var next = cloneShallow(state)
  next.notesMode = !state.notesMode
  return next
}

function togglePause(state) {
  if (!state || state.status !== "playing") return state
  var next = cloneShallow(state)
  if (state.screen !== "play") {
    next.screen = "play"
    next.paused = true
    return next
  }
  next.paused = !state.paused
  return next
}

function tick(state, ms) {
  if (!state || state.status !== "playing" || state.paused || state.screen !== "play") return state
  var next = cloneShallow(state)
  next.elapsedMs = (state.elapsedMs || 0) + ms
  return next
}

function solved(state) {
  for (var i = 0; i < 81; i++) {
    if (state.board[i] !== state.solution[i]) return false
  }
  return true
}

function finishIfNeeded(state) {
  if (state.lives === 0 && state.mode === "challenge") {
    state.status = "lost"
    state.screen = "lost"
    state.paused = false
    state.score = Math.max(0, (state.round || 1) - 1)
    state.message = "No lives left"
    return state
  }
  if (solved(state)) {
    state.paused = false
    if (state.mode === "challenge") {
      state.status = "round"
      state.screen = "round"
      state.score = state.round || 1
      state.clearedElapsedMs = state.elapsedMs || 0
      state.message = "Round clear"
    } else {
      state.status = "won"
      state.screen = "won"
      state.message = "Puzzle complete"
    }
  }
  return state
}

function clearPeerNotes(notes, index, digit) {
  if (!digit || digit < 1 || digit > 9) return
  var mask = ~(1 << digit)
  for (var i = 0; i < 81; i++) {
    if (sameHouse(i, index)) {
      notes[i] = notes[i] & mask
    }
  }
}

function place(state, digit) {
  if (!state || state.screen !== "play" || state.paused || state.status !== "playing") return state
  var index = state.selected
  if (state.given[index]) return state
  if (digit < 0 || digit > 9) return state

  if (state.notesMode && digit !== 0) {
    if (state.board[index] !== 0) return state
    var nextNotes = withHistory(state)
    var bit = 1 << digit
    nextNotes.notes[index] = nextNotes.notes[index] ^ bit
    return nextNotes
  }

  if (state.board[index] === digit && digit !== 0) return state
  if (digit === 0 && state.board[index] === 0 && (state.notes[index] || 0) === 0) return state
  var next = withHistory(state)
  next.board[index] = digit
  next.notes[index] = 0
  if (digit !== 0 && digit !== state.solution[index]) {
    next.mistakes += 1
    if (next.mode === "challenge") next.lives = Math.max(0, next.lives - 1)
  } else if (digit !== 0) {
    clearPeerNotes(next.notes, index, digit)
  }
  return finishIfNeeded(next)
}

function undo(state) {
  if (!state || state.screen !== "play" || !state.history.length) return state
  var past = state.history.slice()
  var snap = past.pop()
  var future = state.future.slice()
  future.push(snapshot(state))
  var next = restore(state, snap)
  next.history = past
  next.future = future
  if (next.status === "lost" || next.status === "won" || next.status === "round") {
    next.status = "playing"
    next.screen = "play"
  }
  return next
}

function redo(state) {
  if (!state || state.screen !== "play" || !state.future.length) return state
  var future = state.future.slice()
  var snap = future.pop()
  var past = state.history.slice()
  past.push(snapshot(state))
  var next = restore(state, snap)
  next.history = past
  next.future = future
  return finishIfNeeded(next)
}

function hint(state) {
  if (!state || state.screen !== "play" || state.paused || state.hintsLeft <= 0) return state
  var index = state.selected
  if (state.given[index] || state.board[index] === state.solution[index]) {
    index = firstEmpty(state.board)
  }
  if (state.given[index] || state.board[index] === state.solution[index]) return state
  var next = withHistory(state)
  var digit = state.solution[index]
  next.selected = index
  next.board[index] = digit
  next.notes[index] = 0
  clearPeerNotes(next.notes, index, digit)
  next.hintsLeft -= 1
  return finishIfNeeded(next)
}

function sameHouse(a, b) {
  if (a === b) return false
  if (Math.floor(a / 9) === Math.floor(b / 9)) return true
  if (a % 9 === b % 9) return true
  var ar = Math.floor(a / 9)
  var ac = a % 9
  var br = Math.floor(b / 9)
  var bc = b % 9
  return Math.floor(ar / 3) === Math.floor(br / 3) && Math.floor(ac / 3) === Math.floor(bc / 3)
}

function noteLabel(mask) {
  var lines = []
  for (var r = 0; r < 3; r++) {
    var parts = []
    for (var c = 0; c < 3; c++) {
      var digit = r * 3 + c + 1
      parts.push((mask & (1 << digit)) ? String(digit) : " ")
    }
    lines.push(parts.join(""))
  }
  return lines.join("\n")
}

function noteBits(mask) {
  var bits = []
  var m = mask || 0
  for (var d = 1; d <= 9; d++) {
    bits.push((m & (1 << d)) !== 0)
  }
  return bits
}

function digitCounts(state) {
  var counts = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  if (!state || !state.board) return counts
  for (var i = 0; i < 81; i++) {
    var val = state.board[i] || 0
    if (val >= 1 && val <= 9) {
      if (state.given[i] === true || !state.solution || !state.solution[i] || val === state.solution[i]) {
        counts[val - 1] += 1
      }
    }
  }
  return counts
}

function cells(state) {
  var out = []
  if (!state || !state.board) return out
  var selectedValue = state.board[state.selected] || 0
  for (var i = 0; i < 81; i++) {
    var value = state.board[i] || 0
    var mask = state.notes[i] || 0
    out.push({
      index: i,
      value: value,
      given: state.given[i] === true,
      wrong: value !== 0 && state.given[i] !== true && value !== state.solution[i],
      notes: noteLabel(mask),
      noteBits: noteBits(mask),
      hasNotes: mask !== 0 && value === 0,
      selected: i === state.selected,
      peer: sameHouse(i, state.selected),
      same: value !== 0 && value === selectedValue
    })
  }
  return out
}

function formatTime(ms) {
  var total = Math.max(0, Math.floor((ms || 0) / 1000))
  var minutes = Math.floor(total / 60)
  var seconds = total % 60
  var text = String(seconds)
  if (text.length < 2) text = "0" + text
  return String(minutes) + ":" + text
}

if (typeof module !== "undefined") {
  module.exports = {
    blank: blank,
    begin: begin,
    toMenu: toMenu,
    resume: resume,
    move: move,
    select: select,
    toggleNotes: toggleNotes,
    togglePause: togglePause,
    tick: tick,
    place: place,
    undo: undo,
    redo: redo,
    hint: hint,
    cells: cells,
    noteBits: noteBits,
    digitCounts: digitCounts,
    formatTime: formatTime
  }
}
