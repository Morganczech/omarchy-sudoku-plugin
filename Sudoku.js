// Sudoku generator and solver. Pure JavaScript so node can test it.
// Digits use bits 1..9. Bit 0 is unused.

var ALL = 0x3fe

var UNITS = buildUnits()
var PEERS = buildPeers(UNITS)

var TARGETS = {
  easy: { min: 36, max: 40, rank: 1 },
  medium: { min: 30, max: 35, rank: 2 },
  hard: { min: 25, max: 29, rank: 3 },
  expert: { min: 22, max: 24, rank: 4 },
  extreme: { min: 22, max: 24, rank: 4 }
}

function buildUnits() {
  var units = []
  var r
  var c
  var b
  var dr
  var dc
  for (r = 0; r < 9; r++) {
    var row = []
    for (c = 0; c < 9; c++) row.push(r * 9 + c)
    units.push(row)
  }
  for (c = 0; c < 9; c++) {
    var col = []
    for (r = 0; r < 9; r++) col.push(r * 9 + c)
    units.push(col)
  }
  for (b = 0; b < 9; b++) {
    var box = []
    var br = Math.floor(b / 3) * 3
    var bc = (b % 3) * 3
    for (dr = 0; dr < 3; dr++) {
      for (dc = 0; dc < 3; dc++) box.push((br + dr) * 9 + (bc + dc))
    }
    units.push(box)
  }
  return units
}

function buildPeers(units) {
  var sets = []
  var i
  for (i = 0; i < 81; i++) sets.push({})
  for (var u = 0; u < units.length; u++) {
    var unit = units[u]
    for (var a = 0; a < unit.length; a++) {
      for (var b = 0; b < unit.length; b++) {
        if (a !== b) sets[unit[a]][unit[b]] = true
      }
    }
  }
  var peers = []
  for (i = 0; i < 81; i++) {
    var list = []
    for (var key in sets[i]) list.push(Number(key))
    peers.push(list)
  }
  return peers
}

function emptyBoard() {
  var board = []
  for (var i = 0; i < 81; i++) board.push(0)
  return board
}

function countBits(mask) {
  mask &= ALL
  var n = 0
  while (mask) {
    n++
    mask &= mask - 1
  }
  return n
}

function firstDigit(mask) {
  mask &= ALL
  for (var d = 1; d <= 9; d++) {
    if (mask & (1 << d)) return d
  }
  return 0
}

function givensOf(board) {
  var n = 0
  for (var i = 0; i < 81; i++) if (board[i] !== 0) n++
  return n
}

function masksFrom(board) {
  var rows = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  var cols = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  var boxes = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  for (var i = 0; i < 81; i++) {
    var digit = board[i]
    if (!digit) continue
    var bit = 1 << digit
    var r = Math.floor(i / 9)
    var c = i % 9
    var b = Math.floor(r / 3) * 3 + Math.floor(c / 3)
    rows[r] |= bit
    cols[c] |= bit
    boxes[b] |= bit
  }
  return { rows: rows, cols: cols, boxes: boxes }
}

function candidateMask(masks, index) {
  var r = Math.floor(index / 9)
  var c = index % 9
  var b = Math.floor(r / 3) * 3 + Math.floor(c / 3)
  return ALL & ~(masks.rows[r] | masks.cols[c] | masks.boxes[b])
}

// limit is the number of solutions to stop at. Returns 0, 1, or >= limit.
// When the first solution is found it is copied onto found.solution.
function countSolutions(board, limit) {
  var work = board.slice()
  var masks = masksFrom(work)
  var found = { count: 0, solution: null }
  search(work, masks, limit || 2, found)
  return found.count
}

function solve(board) {
  var work = board.slice()
  var masks = masksFrom(work)
  var found = { count: 0, solution: null }
  search(work, masks, 1, found)
  return found.solution
}

function search(board, masks, limit, found) {
  if (found.count >= limit) return
  var best = -1
  var bestCount = 10
  var bestMask = 0
  for (var i = 0; i < 81; i++) {
    if (board[i] !== 0) continue
    var mask = candidateMask(masks, i)
    var n = countBits(mask)
    if (n === 0) return
    if (n < bestCount) {
      best = i
      bestCount = n
      bestMask = mask
      if (n === 1) break
    }
  }
  if (best < 0) {
    found.count++
    if (!found.solution) found.solution = board.slice()
    return
  }
  var r = Math.floor(best / 9)
  var c = best % 9
  var b = Math.floor(r / 3) * 3 + Math.floor(c / 3)
  for (var d = 1; d <= 9; d++) {
    var bit = 1 << d
    if ((bestMask & bit) === 0) continue
    board[best] = d
    masks.rows[r] |= bit
    masks.cols[c] |= bit
    masks.boxes[b] |= bit
    search(board, masks, limit, found)
    board[best] = 0
    masks.rows[r] ^= bit
    masks.cols[c] ^= bit
    masks.boxes[b] ^= bit
    if (found.count >= limit) return
  }
}

function mulberry32(seed) {
  var a = seed >>> 0
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    var t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function shuffle(list, rand) {
  for (var i = list.length - 1; i > 0; i--) {
    var j = Math.floor(rand() * (i + 1))
    var tmp = list[i]
    list[i] = list[j]
    list[j] = tmp
  }
  return list
}

function fillRandom(rand) {
  var board = emptyBoard()
  var masks = masksFrom(board)
  function rec() {
    var best = -1
    var bestCount = 10
    var bestMask = 0
    for (var i = 0; i < 81; i++) {
      if (board[i] !== 0) continue
      var mask = candidateMask(masks, i)
      var n = countBits(mask)
      if (n === 0) return false
      if (n < bestCount) {
        best = i
        bestCount = n
        bestMask = mask
        if (n === 1) break
      }
    }
    if (best < 0) return true
    var digits = []
    for (var d = 1; d <= 9; d++) if (bestMask & (1 << d)) digits.push(d)
    shuffle(digits, rand)
    var r = Math.floor(best / 9)
    var c = best % 9
    var b = Math.floor(r / 3) * 3 + Math.floor(c / 3)
    for (var k = 0; k < digits.length; k++) {
      var digit = digits[k]
      var bit = 1 << digit
      board[best] = digit
      masks.rows[r] |= bit
      masks.cols[c] |= bit
      masks.boxes[b] |= bit
      if (rec()) return true
      board[best] = 0
      masks.rows[r] ^= bit
      masks.cols[c] ^= bit
      masks.boxes[b] ^= bit
    }
    return false
  }
  rec()
  return board
}

function symmetricPairs() {
  var pairs = []
  for (var i = 0; i < 40; i++) pairs.push([i, 80 - i])
  pairs.push([40])
  return pairs
}

function candidatesFromBoard(board) {
  var masks = masksFrom(board)
  var cand = []
  for (var i = 0; i < 81; i++) {
    cand.push(board[i] ? (1 << board[i]) : candidateMask(masks, i))
  }
  return cand
}

function placeDigit(board, cand, index, digit) {
  board[index] = digit
  var bit = 1 << digit
  cand[index] = bit
  var peers = PEERS[index]
  for (var p = 0; p < peers.length; p++) cand[peers[p]] &= ~bit
}

function applySingles(board, cand) {
  var i
  for (i = 0; i < 81; i++) {
    if (board[i] !== 0) continue
    if (countBits(cand[i]) === 0) return false
    if (countBits(cand[i]) === 1) {
      placeDigit(board, cand, i, firstDigit(cand[i]))
      return true
    }
  }
  for (var u = 0; u < UNITS.length; u++) {
    var unit = UNITS[u]
    for (var d = 1; d <= 9; d++) {
      var bit = 1 << d
      var where = -1
      var count = 0
      var placed = false
      for (var k = 0; k < 9; k++) {
        var cell = unit[k]
        if (board[cell] === d) {
          placed = true
          break
        }
        if (board[cell] === 0 && (cand[cell] & bit)) {
          count++
          where = cell
        }
      }
      if (!placed && count === 1) {
        placeDigit(board, cand, where, d)
        return true
      }
    }
  }
  return false
}

function applyNakedPairs(board, cand) {
  for (var u = 0; u < UNITS.length; u++) {
    var unit = UNITS[u]
    var cells = []
    for (var k = 0; k < 9; k++) {
      var cell = unit[k]
      if (board[cell] === 0 && countBits(cand[cell]) === 2) cells.push(cell)
    }
    for (var a = 0; a < cells.length; a++) {
      for (var b = a + 1; b < cells.length; b++) {
        if (cand[cells[a]] !== cand[cells[b]]) continue
        var mask = cand[cells[a]]
        var changed = false
        for (var n = 0; n < 9; n++) {
          var other = unit[n]
          if (other === cells[a] || other === cells[b] || board[other] !== 0) continue
          var next = cand[other] & ~mask & ALL
          if (next !== (cand[other] & ALL)) {
            cand[other] = next
            changed = true
          }
        }
        if (changed) return true
      }
    }
  }
  return false
}

function applyHiddenPairs(board, cand) {
  for (var u = 0; u < UNITS.length; u++) {
    var unit = UNITS[u]
    var lists = []
    for (var d = 0; d <= 9; d++) lists.push([])
    for (var k = 0; k < 9; k++) {
      var cell = unit[k]
      if (board[cell] !== 0) continue
      for (d = 1; d <= 9; d++) {
        if (cand[cell] & (1 << d)) lists[d].push(cell)
      }
    }
    for (var d1 = 1; d1 <= 9; d1++) {
      if (lists[d1].length !== 2) continue
      for (var d2 = d1 + 1; d2 <= 9; d2++) {
        if (lists[d2].length !== 2) continue
        if (lists[d1][0] !== lists[d2][0] || lists[d1][1] !== lists[d2][1]) continue
        var keep = (1 << d1) | (1 << d2)
        var changed = false
        for (var n = 0; n < 2; n++) {
          var target = lists[d1][n]
          var next = cand[target] & keep
          if (next !== (cand[target] & ALL)) {
            cand[target] = next
            changed = true
          }
        }
        if (changed) return true
      }
    }
  }
  return false
}

function eliminateOutside(board, cand, digit, cells, inside) {
  var bit = 1 << digit
  var changed = false
  for (var i = 0; i < cells.length; i++) {
    var cell = cells[i]
    if (inside[cell] || board[cell] !== 0) continue
    if (cand[cell] & bit) {
      cand[cell] &= ~bit
      changed = true
    }
  }
  return changed
}

function applyPointing(board, cand) {
  for (var b = 0; b < 9; b++) {
    var unit = UNITS[18 + b]
    var inside = {}
    for (var k = 0; k < 9; k++) inside[unit[k]] = true
    for (var d = 1; d <= 9; d++) {
      var bit = 1 << d
      var hits = []
      for (k = 0; k < 9; k++) {
        var cell = unit[k]
        if (board[cell] === 0 && (cand[cell] & bit)) hits.push(cell)
      }
      if (hits.length < 2) continue
      var row = Math.floor(hits[0] / 9)
      var col = hits[0] % 9
      var sameRow = true
      var sameCol = true
      for (var h = 1; h < hits.length; h++) {
        if (Math.floor(hits[h] / 9) !== row) sameRow = false
        if (hits[h] % 9 !== col) sameCol = false
      }
      if (sameRow && eliminateOutside(board, cand, d, UNITS[row], inside)) return true
      if (sameCol && eliminateOutside(board, cand, d, UNITS[9 + col], inside)) return true
    }
  }
  return false
}

function applyXWing(board, cand) {
  for (var d = 1; d <= 9; d++) {
    var bit = 1 << d
    var rowCols = []
    var r
    var c
    for (r = 0; r < 9; r++) {
      var cols = []
      for (c = 0; c < 9; c++) {
        var cell = r * 9 + c
        if (board[cell] === 0 && (cand[cell] & bit)) cols.push(c)
      }
      rowCols.push(cols)
    }
    for (var r1 = 0; r1 < 9; r1++) {
      if (rowCols[r1].length !== 2) continue
      for (var r2 = r1 + 1; r2 < 9; r2++) {
        if (rowCols[r2].length !== 2) continue
        if (rowCols[r1][0] !== rowCols[r2][0] || rowCols[r1][1] !== rowCols[r2][1]) continue
        var changed = false
        for (r = 0; r < 9; r++) {
          if (r === r1 || r === r2) continue
          for (var n = 0; n < 2; n++) {
            var target = r * 9 + rowCols[r1][n]
            if (board[target] === 0 && (cand[target] & bit)) {
              cand[target] &= ~bit
              changed = true
            }
          }
        }
        if (changed) return true
      }
    }
  }
  return false
}

function isFull(board) {
  for (var i = 0; i < 81; i++) if (board[i] === 0) return false
  return true
}

// rank 1 singles, 2 pairs, 3 pointing or x-wing, 4 needs a guess.
function rate(board) {
  var work = board.slice()
  var cand = candidatesFromBoard(work)
  var maxRank = 0
  for (var guard = 0; guard < 300; guard++) {
    if (isFull(work)) {
      return { solved: true, rank: maxRank || 1, givens: givensOf(board) }
    }
    if (applySingles(work, cand)) {
      maxRank = Math.max(maxRank, 1)
      continue
    }
    if (applyNakedPairs(work, cand) || applyHiddenPairs(work, cand)) {
      maxRank = Math.max(maxRank, 2)
      continue
    }
    if (applyPointing(work, cand) || applyXWing(work, cand)) {
      maxRank = Math.max(maxRank, 3)
      continue
    }
    break
  }
  return { solved: isFull(work), rank: 4, givens: givensOf(board) }
}

function bandMatches(difficulty, rated) {
  var target = TARGETS[difficulty]
  if (!target) return false
  if (rated.givens < target.min || rated.givens > target.max) return false
  if (difficulty === "easy") return rated.solved && rated.rank <= 1
  if (difficulty === "medium") return rated.solved && rated.rank === 2
  if (difficulty === "hard") return rated.solved && rated.rank === 3
  if (difficulty === "expert") return rated.givens >= target.min && rated.givens <= target.max
  return rated.rank >= 4
}

function rankTooHigh(difficulty, rated) {
  if (difficulty === "easy") return rated.rank > 1
  if (difficulty === "medium") return rated.rank > 2
  if (difficulty === "hard") return rated.rank > 3
  return false
}

function carveToward(full, rand, difficulty) {
  var target = TARGETS[difficulty] || TARGETS.easy
  var puzzle = full.slice()
  var pairs = symmetricPairs()
  shuffle(pairs, rand)
  var best = null

  for (var p = 0; p < pairs.length; p++) {
    if (givensOf(puzzle) <= target.min) break
    var pair = pairs[p]
    var saved = []
    var k
    var filled = 0
    for (k = 0; k < pair.length; k++) {
      saved.push(puzzle[pair[k]])
      if (saved[k] !== 0) filled++
    }
    if (!filled) continue
    if (givensOf(puzzle) - filled < target.min) continue
    for (k = 0; k < pair.length; k++) puzzle[pair[k]] = 0
    if (countSolutions(puzzle, 2) !== 1) {
      for (k = 0; k < pair.length; k++) puzzle[pair[k]] = saved[k]
      continue
    }
    if (givensOf(puzzle) > target.max + 4) continue
    var rated = rate(puzzle)
    var matched = bandMatches(difficulty, rated)
    var packed = pack(puzzle.slice(), full, rated, matched)
    if (!best || matched) best = packed
    if (matched) return packed
    if (rankTooHigh(difficulty, rated)) {
      for (k = 0; k < pair.length; k++) puzzle[pair[k]] = saved[k]
    }
  }

  // Rotational pairs often stall above the expert band. Lift one clue at a time
  // after that, still requiring a unique solution.
  var order = []
  for (var i = 0; i < 81; i++) order.push(i)
  shuffle(order, rand)
  for (i = 0; i < order.length; i++) {
    if (givensOf(puzzle) <= target.min) break
    var cell = order[i]
    if (puzzle[cell] === 0) continue
    if (givensOf(puzzle) - 1 < target.min) continue
    var previous = puzzle[cell]
    puzzle[cell] = 0
    if (countSolutions(puzzle, 2) !== 1) {
      puzzle[cell] = previous
      continue
    }
    if (givensOf(puzzle) > target.max + 4) continue
    var ratedSingle = rate(puzzle)
    var matchedSingle = bandMatches(difficulty, ratedSingle)
    var packedSingle = pack(puzzle.slice(), full, ratedSingle, matchedSingle)
    if (!best || matchedSingle) best = packedSingle
    if (matchedSingle) return packedSingle
    if (rankTooHigh(difficulty, ratedSingle)) puzzle[cell] = previous
  }

  if (best) return best
  var ratedFallback = rate(puzzle)
  return pack(puzzle.slice(), full, ratedFallback, bandMatches(difficulty, ratedFallback))
}

function pack(board, solution, rated, matched) {
  return {
    board: board,
    solution: solution,
    givens: rated.givens,
    rank: rated.rank,
    matched: matched
  }
}

function generate(difficulty, seed) {
  var target = TARGETS[difficulty] || TARGETS.easy
  var base = (seed >>> 0) || 1
  var attempts = difficulty === "easy" ? 8 : difficulty === "extreme" ? 20 : difficulty === "medium" ? 48 : 24
  var fallback = null
  for (var attempt = 0; attempt < attempts; attempt++) {
    var rand = mulberry32(base + attempt * 9973)
    var full = fillRandom(rand)
    var packed = carveToward(full, rand, difficulty)
    if (countSolutions(packed.board, 2) !== 1) continue
    if (!fallback || packed.matched) fallback = packed
    if (packed.matched) return packed
  }
  if (fallback) return fallback
  var randFallback = mulberry32(base)
  var fullFallback = fillRandom(randFallback)
  return carveToward(fullFallback, randFallback, difficulty)
}

function parseGrid(text) {
  var digits = String(text || "").replace(/\D/g, "")
  var board = emptyBoard()
  for (var i = 0; i < 81 && i < digits.length; i++) board[i] = Number(digits.charAt(i))
  return board
}

if (typeof module !== "undefined") {
  module.exports = {
    ALL: ALL,
    TARGETS: TARGETS,
    emptyBoard: emptyBoard,
    countSolutions: countSolutions,
    solve: solve,
    rate: rate,
    generate: generate,
    parseGrid: parseGrid,
    givensOf: givensOf
  }
}
