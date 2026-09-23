local M = {}

-- Pure calculation seam used by every path that reserves capacity for fluids.
function M.required(activeFieldStrength, baselineFieldStrength, refillFieldStrengthFloor,
    storedTotal, reservation)
  return math.max(
    activeFieldStrength,
    baselineFieldStrength,
    refillFieldStrengthFloor,
    storedTotal + reservation,
    activeFieldStrength + reservation
  )
end

return M
