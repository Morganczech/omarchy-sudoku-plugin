// JSON save and stats. File IO stays in the QML overlay.

function emptyStats() {
  return {
    version: 1,
    classicWins: 0,
    classicBestMs: {},
    challengeBestRound: 0,
    challengeBestTimeMs: 0,
    challengeBestMistakes: 0,
    challengeTotalMistakes: 0,
    challengeRuns: 0
  }
}

function copyBoard(board) {
  var out = []
  for (var i = 0; i < 81; i++) out.push(board && board[i] ? Number(board[i]) : 0)
  return out
}

function copyNotes(notes) {
  var out = []
  for (var i = 0; i < 81; i++) out.push(notes && notes[i] ? (Number(notes[i]) & 0x3fe) : 0)
  return out
}

function copyGiven(given) {
  var out = []
  for (var i = 0; i < 81; i++) out.push(given ? given[i] === true : false)
  return out
}

function canPersist(state) {
  if (!state || !state.mode) return false
  if (state.status === "lost") return false
  if (state.status !== "playing" && state.status !== "won" && state.status !== "round") return false
  return true
}

function serialize(state) {
  if (!canPersist(state)) return null
  return {
    version: 1,
    mode: state.mode,
    difficulty: state.difficulty,
    round: state.round || 1,
    lives: state.lives,
    mistakes: state.mistakes || 0,
    hintsLeft: state.hintsLeft || 0,
    notesMode: state.notesMode === true,
    paused: false,
    elapsedMs: state.elapsedMs || 0,
    clearedElapsedMs: state.clearedElapsedMs || 0,
    board: copyBoard(state.board),
    given: copyGiven(state.given),
    solution: copyBoard(state.solution),
    notes: copyNotes(state.notes),
    selected: state.selected || 0,
    status: state.status,
    score: state.score || 0
  }
}

function parse(raw) {
  if (!raw || !String(raw).trim()) return null
  var data
  try {
    data = JSON.parse(raw)
  } catch (e) {
    return null
  }
  if (!data || data.version !== 1 || !data.mode) return null
  if (!data.board || data.board.length !== 81 || !data.solution || data.solution.length !== 81) return null
  if (data.status === "lost") return null
  var status = data.status || "playing"
  var screen = status === "won" ? "won" : status === "round" ? "round" : "play"
  return {
    screen: screen,
    mode: data.mode,
    difficulty: data.difficulty || "easy",
    round: data.round || 1,
    lives: data.mode === "classic" ? -1 : Number(data.lives || 0),
    mistakes: data.mistakes || 0,
    hintsLeft: data.hintsLeft || 0,
    notesMode: data.notesMode === true,
    paused: false,
    elapsedMs: data.elapsedMs || 0,
    clearedElapsedMs: data.clearedElapsedMs || 0,
    board: copyBoard(data.board),
    given: copyGiven(data.given),
    solution: copyBoard(data.solution),
    notes: copyNotes(data.notes),
    selected: Math.max(0, Math.min(80, data.selected || 0)),
    status: status,
    score: data.score || 0,
    history: [],
    future: [],
    message: ""
  }
}

function parseStats(raw) {
  var stats = emptyStats()
  if (!raw || !String(raw).trim()) return stats
  try {
    var data = JSON.parse(raw)
    if (!data || data.version !== 1) return stats
    stats.classicWins = data.classicWins || 0
    stats.classicBestMs = data.classicBestMs || {}
    stats.challengeBestRound = data.challengeBestRound || 0
    stats.challengeBestTimeMs = data.challengeBestTimeMs || 0
    stats.challengeBestMistakes = data.challengeBestMistakes || 0
    stats.challengeTotalMistakes = data.challengeTotalMistakes || 0
    stats.challengeRuns = data.challengeRuns || 0
  } catch (e) {
    return emptyStats()
  }
  return stats
}

function recordClassicWin(stats, difficulty, elapsedMs) {
  var next = parseStats(JSON.stringify(stats || emptyStats()))
  next.classicWins += 1
  var best = next.classicBestMs[difficulty]
  if (!best || elapsedMs < best) next.classicBestMs[difficulty] = elapsedMs
  return next
}

function recordChallengeRound(stats, completedRounds, clearedElapsedMs, mistakes) {
  var next = parseStats(JSON.stringify(stats || emptyStats()))
  var rounds = completedRounds || 0
  var timeMs = clearedElapsedMs || 0
  var errs = mistakes || 0
  if (rounds > next.challengeBestRound || (rounds === next.challengeBestRound && rounds > 0 && (next.challengeBestTimeMs === 0 || timeMs < next.challengeBestTimeMs))) {
    next.challengeBestRound = rounds
    next.challengeBestTimeMs = timeMs
    next.challengeBestMistakes = errs
  }
  return next
}

function recordChallengeEnd(stats, completedRounds, clearedElapsedMs, mistakes) {
  var next = recordChallengeRound(stats, completedRounds, clearedElapsedMs, mistakes)
  next.challengeRuns += 1
  next.challengeTotalMistakes = (next.challengeTotalMistakes || 0) + (mistakes || 0)
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyStats: emptyStats,
    serialize: serialize,
    parse: parse,
    parseStats: parseStats,
    recordClassicWin: recordClassicWin,
    recordChallengeRound: recordChallengeRound,
    recordChallengeEnd: recordChallengeEnd
  }
}
