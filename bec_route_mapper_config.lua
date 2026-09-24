local loaded, all = pcall(function() return require("bec_config").load("bec.conf") end)
if not loaded then error("cannot load bec.conf: " .. tostring(all), 0) end
local automationLoaded, automation = pcall(require, "bec_automation_config")
if not automationLoaded then error("cannot load bec_automation_config.lua: " .. tostring(automation), 0) end
local source = all.routeMapper or {}
local configSides = require("bec_config").sides

local expectedFluids = {}
for _, entry in ipairs(automation.fluids or {}) do expectedFluids[#expectedFluids + 1] = entry.source end
local testSides = {}
for _, entry in ipairs(source.testSides or {}) do
  local name = tostring(entry.name or entry.value or ""):lower()
  testSides[#testSides + 1] = { value = configSides[name] or configSides.default, name = name }
end

local result = {
  schemaVersion = 1,
  cacheInterfaceAddress = automation.refill and automation.refill.cacheInterfaceAddress,
  referenceInterfaceAddress = source.referenceInterfaceAddress,
  redstoneAddresses = source.redstoneAddresses,
  testSides = testSides,
  expectedFluids = expectedFluids,
  allowNonEmptyCache = false,
  requireAllExpectedInReference = false,
  activeSignal = 15,
  inactiveSignal = 0,
  minDetectedDelta = 1,
  timings = {
    poll = 0.10,
    stableFor = 0.75,
    stableTimeout = 30,
    probeTimeout = 20,
    postOffDelay = 2,
    statusInterval = 2,
    recoveryTimeout = 10,
  },
  outputFile = "bec_fluid_routes.conf",
  partialOutputFile = "bec_fluid_routes.partial.conf",
  protectedControls = {
    { label = "material/item-cache whole-batch output", address = automation.redstone.nodeAddress, side = automation.redstone.nodeToggleSide },
    { label = "material/fluid-cache whole-batch output", address = automation.redstone.generatorAddress, side = automation.redstone.generatorToggleSide },
    { label = "automatic-refill/entangler AE toggle bus", address = automation.refill.entanglerAddress, side = automation.refill.entanglerToggleSide },
    { label = "synthesis-active output", address = automation.redstone.synthesisAddress, side = automation.redstone.synthesisSide },
    { label = "BEC automation HALT output", address = automation.redstone.haltAddress, side = automation.redstone.haltSide },
  },
}

local nanite = automation.nanite or {}
if nanite.enabled ~= false and type(nanite.ejectRedstoneAddress) == "string"
    and nanite.ejectRedstoneAddress ~= "" then
  result.protectedControls[#result.protectedControls + 1] = {
    label = "nanite eject output",
    address = nanite.ejectRedstoneAddress,
    side = nanite.ejectSide,
  }
end

return result
