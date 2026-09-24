local loaded, external = pcall(function()
  return require("bec_config").load("bec.conf").automation
end)
if not loaded then
  error("cannot load bec.conf: " .. tostring(external), 0)
end
if type(external) ~= "table" then error("bec.conf is missing the automation section", 0) end

-- Only machine-specific wiring remains in bec.conf. The values below are
-- fixed by the automation program and are intentionally not editable there.
local redstone = external.redstone or {}
local nanite = external.nanite or {}
local refill = external.refill or {}

local MiB = 1024 * 1024
local function alignedCache(mebibytes, unit)
  return math.floor(mebibytes * MiB / unit) * unit
end

return {
  schemaVersion = 12,

  storageAddress = external.storageAddress,
  gateAddress = external.gateAddress,
  cacheInterfaceAddress = external.cacheInterfaceAddress,
  cacheInterfaceType = external.cacheInterfaceType,

  buffers = external.buffers,

  redstone = {
    nodeAddress = redstone.nodeAddress,
    generatorAddress = redstone.generatorAddress,
    synthesisAddress = redstone.synthesisAddress,
    haltAddress = redstone.haltAddress,
    nodeToggleSide = redstone.nodeToggleSide,
    generatorToggleSide = redstone.generatorToggleSide,
    synthesisSide = redstone.synthesisSide,
    haltSide = redstone.haltSide,
    connectSignal = 15,
    disconnectSignal = 0,
  },

  nanite = {
    enabled = true,
    storageBusAddress = nanite.storageBusAddress,
    inputSide = nanite.inputSide,
    ejectRedstoneAddress = nanite.ejectRedstoneAddress,
    ejectSide = nanite.ejectSide,
    transposerAddress = nanite.transposerAddress,
    targetSide = nanite.targetSide,
    targetOutputSlot = nanite.targetOutputSlot,
    activeSignal = 15,
    inactiveSignal = 0,
    ejectTimeout = 10,
    supplyTimeout = 30,
    poll = 0.5,
    enableCache = false,
    oreByTier = {
      [1] = "naniteCarbon",
      [2] = "naniteSilver",
      [3] = "naniteGold",
      [4] = "naniteTranscendentMetal",
      [5] = "naniteSixPhasedCopper",
      [6] = "naniteWhiteDwarfMatter",
      [7] = "naniteBlackDwarfMatter",
      [8] = "naniteUniversium",
      [9] = "naniteEternity",
      [10] = "naniteMagmatter",
    },
  },

  refill = {
    enabled = true,
    routeModule = refill.routeModule,
    cacheInterfaceAddress = refill.cacheInterfaceAddress,
    cacheInterfaceType = refill.cacheInterfaceType,
    entanglerAddress = refill.entanglerAddress,
    entanglerToggleSide = refill.entanglerToggleSide,
    activityAddress = refill.activityAddress,
    activitySide = refill.activitySide,
    activityThreshold = 1,
    connectSignal = 15,
    disconnectSignal = 0,
    poll = 0.05,
    routeTimeout = 30,
    conversionTimeout = 1800,
    checkInterval = 5,
    drainedWaitTimeout = 240,
    pulseDuration = 1,
    pulseInterval = 1,
  },

  ui = {
    enabled = true,
    width = 100,
    height = 30,
    refreshInterval = 1.0,
    processedRecipeFile = "/home/bec_processed_recipes.dat",
  },

  nodes = {
    expectedCount = 16,
    maxParallelPerNode = 64,
    addresses = {},
  },

  fluids = {
    { source = "molten.neutronium", condensate = "entangled_neutronium", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.cosmicneutronium", condensate = "entangled_cosmicneutronium", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.bedrockium", condensate = "entangled_bedrockium", unit = 144, target = alignedCache(6300, 144), outputPerSecond = 576000000 },
    { source = "molten.chromaticglass", condensate = "entangled_chromaticglass", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.celestialtungsten", condensate = "entangled_celestialtungsten", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.infinity", condensate = "entangled_infinity", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.hypogen", condensate = "entangled_hypogen", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.transcendentmetal", condensate = "entangled_transcendentmetal", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "dimensionallyshiftedsuperfluid", condensate = "entangled_dimshiftedsuperfluid", unit = 1000, target = alignedCache(128, 1000), outputPerSecond = 2880000 },
    { source = "phononmedium", condensate = "entangled_phononmedium", unit = 1000, target = alignedCache(128, 1000), outputPerSecond = 2880000 },
    { source = "quarkgluonplasma", condensate = "entangled_quarkgluonplasma", unit = 1000, target = alignedCache(128, 1000), outputPerSecond = 2880000 },
    { source = "molten.spacetime", condensate = "entangled_spacetime", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "temporalfluid", condensate = "entangled_time", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "spatialfluid", condensate = "entangled_space", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "boundlesscosmicsolder", condensate = "entangled_cosmicsolder", unit = 1000, target = alignedCache(128, 1000), outputPerSecond = 2880000 },
    { source = "molten.magnetohydrodynamicallyconstrainedstarmatter", condensate = "entangled_mhdcsm", unit = 144, target = alignedCache(16, 144), outputPerSecond = 2880000 },
    { source = "molten.magmatter", condensate = "entangled_magmatter", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.universium", condensate = "entangled_universium", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
    { source = "molten.eternity", condensate = "entangled_eternity", unit = 144, target = alignedCache(128, 144), outputPerSecond = 2880000 },
  },

  orderCounting = {
    fallbackDivisor = 1,
    recipeDivisors = {
      ["01f4a7e0"] = 2,
      ["074e8946"] = 64,
      ["136c78dc"] = 4,
      ["3b3d449b"] = 2,
      ["751d1813"] = 2,
      ["807691b7"] = 6,
      ["c3307e91"] = 4,
      ["fa6f4c32"] = 4,
      ["4f5dd565"] = 4,
      ["5823282a"] = 4,
      ["b02e3d7c"] = 4,
      ["5823282e"] = 4,
    },
    itemAliases = {
      ["dreamcraft:CircuitUEV0"] = "#circuitBio",
      ["gregtech:gt.metaitem.0332120"] = "#circuitBio",
      ["gregtech:gt.metaitem.0332156"] = "#circuitBio",
      ["gregtech:gt.metaitem.0332167"] = "#circuitBio",
      ["gregtech:gt.metaitem.0332170"] = "#circuitBio",
      ["dreamcraft:CircuitUIV0"] = "#circuitOptical",
      ["gregtech:gt.metaitem.0332157"] = "#circuitOptical",
      ["gregtech:gt.metaitem.0332168"] = "#circuitOptical",
      ["gregtech:gt.metaitem.0332171"] = "#circuitOptical",
      ["gregtech:gt.metaitem.0332174"] = "#circuitOptical",
      ["dreamcraft:PikoCircuit0"] = "#circuitExotic",
      ["dreamcraft:CircuitUMV0"] = "#circuitExotic",
      ["gregtech:gt.metaitem.0332169"] = "#circuitExotic",
      ["gregtech:gt.metaitem.0332172"] = "#circuitExotic",
      ["gregtech:gt.metaitem.0332175"] = "#circuitExotic",
      ["dreamcraft:QuantumCircuit0"] = "#circuitCosmic",
      ["dreamcraft:CircuitUXV0"] = "#circuitCosmic",
      ["gregtech:gt.metaitem.0332173"] = "#circuitCosmic",
      ["gregtech:gt.metaitem.0332176"] = "#circuitCosmic",
      ["dreamcraft:CircuitMAX0"] = "#circuitTranscendent",
      ["dreamcraft:PlanckCircuit0"] = "#circuitTranscendent",
      ["gregtech:gt.metaitem.0332177"] = "#circuitTranscendent",
    },
  },

  timings = {
    poll = 0.25,
    orderSettle = 1.0,
    emptySettle = 1.0,
    filterVerifyDelay = 0.15,
    nodeTransferPulse = 1.0,
    orderFluidTransferPulse = 1.0,
    nodeStartGrace = 3.0,
    condensateWaitTimeout = 4800,
    orderRunTimeout = 7200,
    statusInterval = 10,
    cooldown = 1.0,
  },

  safety = {
    allowZeroTargetStock = false,
    requireConfiguredStockAtStartup = false,
    allowFieldStrengthBelowCurrentStock = false,
  },

  logFile = "/home/bec_automation.log",
}
