// Survival ladder. Lives and the next difficulty live in one config object.

var LADDER = ["easy", "medium", "hard", "expert", "extreme"]

function defaultConfig() {
  return {
    startLives: 3,
    bonusLives: 2,
    maxLives: 0,
    hintsPerPuzzle: 3
  }
}

function nextDifficulty(difficulty) {
  var index = LADDER.indexOf(difficulty)
  if (index < 0) return LADDER[0]
  if (index >= LADDER.length - 1) return LADDER[LADDER.length - 1]
  return LADDER[index + 1]
}

function livesAfterClear(lives, config) {
  var settings = config || defaultConfig()
  var next = (lives || 0) + settings.bonusLives
  if (settings.maxLives > 0) next = Math.min(next, settings.maxLives)
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    LADDER: LADDER,
    defaultConfig: defaultConfig,
    nextDifficulty: nextDifficulty,
    livesAfterClear: livesAfterClear
  }
}
