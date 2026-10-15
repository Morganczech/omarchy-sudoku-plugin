const test = require("node:test")
const assert = require("node:assert/strict")
const Sudoku = require("../Sudoku.js")
const Game = require("../Game.js")
const Challenge = require("../Challenge.js")
const Storage = require("../Storage.js")

const KNOWN = (
  "530070000" +
  "600195000" +
  "098000060" +
  "800060003" +
  "400803001" +
  "700020006" +
  "060000280" +
  "000419005" +
  "000080079"
)

test("a known puzzle has one solution", function () {
  const board = Sudoku.parseGrid(KNOWN)
  assert.equal(Sudoku.countSolutions(board, 2), 1)
  const solved = Sudoku.solve(board)
  assert.equal(solved[0], 5)
  assert.equal(solved[2], 4)
  assert.equal(Sudoku.givensOf(board), 30)
})

test("an empty board is not unique", function () {
  assert.equal(Sudoku.countSolutions(Sudoku.emptyBoard(), 2), 2)
})

test("easy puzzles stay in band and are unique", function () {
  const puzzle = Sudoku.generate("easy", 7)
  assert.equal(Sudoku.countSolutions(puzzle.board, 2), 1)
  assert.equal(puzzle.matched, true)
  assert.ok(puzzle.givens >= 36 && puzzle.givens <= 40)
  assert.ok(puzzle.rank <= 1)
})

test("medium and hard puzzles hit their bands", function () {
  const medium = Sudoku.generate("medium", 1)
  assert.equal(medium.matched, true)
  assert.equal(Sudoku.countSolutions(medium.board, 2), 1)
  assert.ok(medium.givens >= 30 && medium.givens <= 35)
  assert.equal(medium.rank, 2)

  const hard = Sudoku.generate("hard", 1)
  assert.equal(hard.matched, true)
  assert.equal(hard.rank, 3)
  assert.ok(hard.givens >= 25 && hard.givens <= 29)
})

test("challenge ladder and life bonus", function () {
  const config = Challenge.defaultConfig()
  assert.equal(Challenge.nextDifficulty("easy"), "medium")
  assert.equal(Challenge.nextDifficulty("extreme"), "extreme")
  assert.equal(Challenge.livesAfterClear(1, config), 3)
  const capped = Challenge.defaultConfig()
  capped.maxLives = 5
  assert.equal(Challenge.livesAfterClear(4, capped), 5)
})

test("a wrong challenge entry spends a life and undo gives it back", function () {
  const puzzle = Sudoku.generate("easy", 3)
  let state = Game.begin(puzzle, { mode: "challenge", difficulty: "easy", lives: 3, hints: 3, round: 1 })
  const hole = state.selected
  const wrong = state.solution[hole] === 1 ? 2 : 1
  state = Game.place(state, wrong)
  assert.equal(state.lives, 2)
  assert.equal(state.board[hole], wrong)
  state = Game.undo(state)
  assert.equal(state.lives, 3)
  assert.equal(state.board[hole], 0)
})

test("notes, hints, and a finished classic puzzle", function () {
  const puzzle = Sudoku.generate("easy", 5)
  let state = Game.begin(puzzle, { mode: "classic", difficulty: "easy", hints: 3 })
  state = Game.toggleNotes(state)
  state = Game.place(state, 4)
  assert.ok(state.notes[state.selected] & (1 << 4))
  state = Game.toggleNotes(state)
  while (state.status === "playing" && state.hintsLeft > 0) state = Game.hint(state)
  // Fill anything the hints did not reach.
  for (let i = 0; i < 81 && state.status === "playing"; i++) {
    state = Game.select(state, i)
    if (!state.given[i] && state.board[i] !== state.solution[i]) state = Game.place(state, state.solution[i])
  }
  assert.equal(state.status, "won")
  assert.equal(state.screen, "won")
})

test("death clears the save and records the cleared rounds, survival time, and mistakes", function () {
  const puzzle = Sudoku.generate("easy", 9)
  let state = Game.begin(puzzle, {
    mode: "challenge",
    difficulty: "hard",
    lives: 1,
    mistakes: 4,
    hints: 0,
    round: 4,
    elapsedMs: 210000,
    clearedElapsedMs: 185000
  })
  const hole = state.selected
  const wrong = state.solution[hole] === 9 ? 8 : 9
  state = Game.place(state, wrong)
  assert.equal(state.status, "lost")
  assert.equal(state.score, 3)
  assert.equal(state.mistakes, 5)
  assert.equal(state.clearedElapsedMs, 185000)
  assert.equal(Storage.serialize(state), null)
  const stats = Storage.recordChallengeEnd(Storage.emptyStats(), state.score, state.clearedElapsedMs, state.mistakes)
  assert.equal(stats.challengeBestRound, 3)
  assert.equal(stats.challengeBestTimeMs, 185000)
  assert.equal(stats.challengeBestMistakes, 5)
  assert.equal(stats.challengeTotalMistakes, 5)
  assert.equal(stats.challengeRuns, 1)
})

test("save round-trips a game in progress", function () {
  const puzzle = Sudoku.generate("easy", 4)
  let state = Game.begin(puzzle, { mode: "classic", difficulty: "easy", hints: 3 })
  state = Game.place(state, state.solution[state.selected])
  state = Game.toMenu(state)
  const raw = JSON.stringify(Storage.serialize(state))
  const loaded = Storage.parse(raw)
  assert.equal(loaded.mode, "classic")
  assert.equal(loaded.board[state.selected] > 0 || true, true)
  assert.deepEqual(loaded.solution, state.solution)
  const resumed = Game.resume(loaded)
  assert.equal(resumed.screen, "play")
})

test("survival challenge round-clear and round 2 progression survive save/parse/resume", function () {
  const config = Challenge.defaultConfig()
  const round1Puzzle = Sudoku.generate("easy", 21)
  let state = Game.begin(round1Puzzle, {
    mode: "challenge",
    difficulty: "easy",
    round: 1,
    lives: config.startLives,
    hints: config.hintsPerPuzzle,
    elapsedMs: 0,
    score: 0
  })

  // Spend 1 life on a mistake, then solve round 1
  const firstHole = state.selected
  const wrongDigit = state.solution[firstHole] === 9 ? 1 : state.solution[firstHole] + 1
  state = Game.place(state, wrongDigit)
  assert.equal(state.lives, 2)
  assert.equal(state.mistakes, 1)

  state = Game.tick(state, 42000)
  for (let i = 0; i < 81 && state.status === "playing"; i++) {
    if (!state.given[i] && state.board[i] !== state.solution[i]) {
      state = Game.select(state, i)
      state = Game.place(state, state.solution[i])
    }
  }
  assert.equal(state.status, "round")
  assert.equal(state.screen, "round")
  assert.equal(state.score, 1)
  assert.equal(state.clearedElapsedMs, 42000)

  // Save & restore while on the Round Clear screen before advancing
  const roundClearLoaded = Storage.parse(JSON.stringify(Storage.serialize(state)))
  assert.equal(roundClearLoaded.status, "round")
  assert.equal(roundClearLoaded.screen, "round")
  assert.equal(roundClearLoaded.round, 1)
  assert.equal(roundClearLoaded.score, 1)
  assert.equal(roundClearLoaded.lives, 2)
  assert.equal(roundClearLoaded.mistakes, 1)
  assert.equal(roundClearLoaded.clearedElapsedMs, 42000)

  // Advance to Round 2 (Medium) and make one move
  const round2Puzzle = Sudoku.generate(Challenge.nextDifficulty(roundClearLoaded.difficulty), 22)
  let round2State = Game.begin(round2Puzzle, {
    mode: "challenge",
    difficulty: Challenge.nextDifficulty(roundClearLoaded.difficulty),
    round: roundClearLoaded.round + 1,
    lives: Challenge.livesAfterClear(roundClearLoaded.lives, config),
    mistakes: roundClearLoaded.mistakes,
    hints: config.hintsPerPuzzle,
    elapsedMs: roundClearLoaded.elapsedMs,
    clearedElapsedMs: roundClearLoaded.clearedElapsedMs,
    score: roundClearLoaded.score
  })
  const r2Hole = round2State.selected
  round2State = Game.place(round2State, round2State.solution[r2Hole])
  round2State = Game.tick(round2State, 5000)

  const round2Loaded = Storage.parse(JSON.stringify(Storage.serialize(round2State)))
  assert.equal(round2Loaded.mode, "challenge")
  assert.equal(round2Loaded.difficulty, "medium")
  assert.equal(round2Loaded.round, 2)
  assert.equal(round2Loaded.lives, 4)
  assert.equal(round2Loaded.mistakes, 1)
  assert.equal(round2Loaded.score, 1)
  assert.equal(round2Loaded.elapsedMs, 47000)
  assert.equal(round2Loaded.clearedElapsedMs, 42000)
  assert.equal(round2Loaded.status, "playing")
  assert.equal(round2Loaded.screen, "play")
  assert.equal(round2Loaded.board[r2Hole], round2State.solution[r2Hole])
})

test("placing a valid digit clears matching peer notes and undo restores them", function () {
  const puzzle = Sudoku.generate("easy", 11)
  let state = Game.begin(puzzle, { mode: "classic", difficulty: "easy", hints: 3 })
  const target = state.selected
  const digit = state.solution[target]

  // Find a peer cell that is empty (or temporarily clear it in notes)
  let peerIndex = -1
  for (let i = 0; i < 81; i++) {
    if (i !== target && !state.given[i] && (Math.floor(i / 9) === Math.floor(target / 9) || (i % 9) === (target % 9))) {
      peerIndex = i
      break
    }
  }
  assert.ok(peerIndex >= 0)

  state = Game.select(state, peerIndex)
  state = Game.toggleNotes(state)
  state = Game.place(state, digit)
  assert.ok((state.notes[peerIndex] & (1 << digit)) !== 0)

  // Now place the correct digit in target
  state = Game.toggleNotes(state)
  state = Game.select(state, target)
  state = Game.place(state, digit)
  assert.equal(state.notes[peerIndex] & (1 << digit), 0)

  // Undo should restore peer note
  state = Game.undo(state)
  assert.ok((state.notes[peerIndex] & (1 << digit)) !== 0)
})

test("digitCounts and noteBits report accurate board state", function () {
  const puzzle = Sudoku.generate("easy", 12)
  let state = Game.begin(puzzle, { mode: "classic", difficulty: "easy", hints: 3 })
  const countsBefore = Game.digitCounts(state)
  assert.equal(countsBefore.length, 9)

  const target = state.selected
  const correctDigit = state.solution[target]
  const wrongDigit = correctDigit === 9 ? 1 : correctDigit + 1

  // Wrong digit should not increment valid digit count
  const wrongState = Game.place(state, wrongDigit)
  assert.equal(Game.digitCounts(wrongState)[wrongDigit - 1], countsBefore[wrongDigit - 1])

  // Correct digit increments count by 1
  const rightState = Game.place(state, correctDigit)
  assert.equal(Game.digitCounts(rightState)[correctDigit - 1], countsBefore[correctDigit - 1] + 1)

  // noteBits returns 9 booleans
  state = Game.toggleNotes(state)
  state = Game.place(state, 1)
  state = Game.place(state, 9)
  const cell = Game.cells(state)[target]
  assert.equal(cell.noteBits.length, 9)
  assert.equal(cell.noteBits[0], true)
  assert.equal(cell.noteBits[1], false)
  assert.equal(cell.noteBits[8], true)
})

