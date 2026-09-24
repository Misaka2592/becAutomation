local M = {}

local COMPONENT_TYPES = {
  "bec_storage", "bec_diode", "bec_io_node", "me_interface", "me_storagebus", "transposer", "redstone",
}

function M.discover(component)
  for _, componentType in ipairs(COMPONENT_TYPES) do
    for address in component.list(componentType, true) do
      local methods = component.methods(address) or {}
      local names = {}
      for method in pairs(methods) do names[#names + 1] = method end
      table.sort(names)
      print(componentType .. "  " .. address)
      print("  methods=" .. table.concat(names, ","))
    end
  end
end

function M.check(context)
  local config = context.config
  local output = context.print or print
  local checked = context.checked
  local fail = context.fail or function(message) error(message, 0) end
  local formatInteger = context.formatInteger
  local sumValues = context.sumValues

  output("Components found")
  output("  storage=" .. context.storage.address)
  output("  gate=" .. context.gate.address)
  output("  material-cache=" .. context.cache.address .. " (" .. context.cache.type .. ")")
  output("  item-cache=" .. context.itemCache.address .. " (" .. context.itemCache.type .. ")")
  output("  fluid-cache=" .. context.fluidCache.address .. " (" .. context.fluidCache.type .. ")")
  output("  node-redstone=" .. context.nodeRedstone.address .. " side=" .. config.redstone.nodeToggleSide)
  output("  node-transfer-pulse=" .. tostring(config.timings.nodeTransferPulse) .. "s")
  output("  order-fluid-transfer-redstone="
    .. context.generatorRedstone.address .. " side=" .. config.redstone.generatorToggleSide)
  output("  synthesis-active-redstone="
    .. context.synthesisRedstone.address .. " side=" .. config.redstone.synthesisSide)
  output("  synthesis-active-output=" .. tostring(checked(
    "read synthesis-active output",
    context.synthesisRedstone.getOutput,
    config.redstone.synthesisSide
  )))
  output("  halt-redstone=" .. context.haltRedstone.address .. " side=" .. config.redstone.haltSide)
  output("  halt-output=" .. tostring(checked(
    "read HALT output",
    context.haltRedstone.getOutput,
    config.redstone.haltSide
  )))
  if context.naniteController then
    local naniteConfig = config.nanite
    local status = context.naniteController:getStatus()
    output("  nanite-controller-node-count=" .. tostring(status.controllerNodeCount or 0))
    for _, node in ipairs(status.nodes or {}) do
      output("  nanite-controller-node=" .. tostring(node.address)
        .. " required-tier=" .. tostring(node.requiredTier)
        .. " provided-tier=" .. tostring(node.providedTier))
    end
    output("  nanite-storage-bus=" .. context.naniteStorageBus.address .. " side=" .. naniteConfig.inputSide)
    output("  nanite-eject-redstone=" .. context.naniteEjectRedstone.address .. " side=" .. naniteConfig.ejectSide)
    output("  nanite-eject-output=" .. tostring(checked(
      "read nanite eject output", context.naniteEjectRedstone.getOutput, naniteConfig.ejectSide
    )))
    output("  nanite-transposer=" .. context.naniteTransposer.address .. " side=" .. naniteConfig.targetSide
      .. " slot=" .. naniteConfig.targetOutputSlot)
    output("  nanite-required-tier=" .. tostring(status.requiredTier))
    output("  nanite-provided-tier=" .. tostring(status.providedTier))
    output("  nanite-matched-node-count=" .. tostring(status.matchedNodeCount or 0))
    output("  nanite-control-stage=" .. status.stage .. " commanded-filter=" .. status.filter)
    if status.requiredError or status.providedError then
      fail("cannot read nanite tier status: " .. tostring(status.requiredError or status.providedError))
    end
  else
    output("  nanite-control=disabled")
  end
  if (config.refill or {}).enabled then
    output("  refill-cache=" .. context.refillCache.address .. " (" .. context.refillCache.type .. ")")
    output("  refill-entangler-redstone=" .. context.refillLinkRedstone.address
      .. " side=" .. config.refill.entanglerToggleSide)
    output("  refill-entangler-activity-redstone=" .. context.refillActivityRedstone.address
      .. " side=" .. config.refill.activitySide)
    output("  refill-unused-route-output=" .. context.routeConfig.unusedOutput.address
      .. " side=" .. context.routeConfig.unusedOutput.side .. " (kept off)")
    output("  refill-fluid-config:")
    for _, entry in ipairs(config.fluids) do
      output(string.format(
        "    %s target=%s rate=%s mB/s",
        entry.source,
        formatInteger(entry.target),
        formatInteger(entry.outputPerSecond)
      ))
    end
    output("  refill-staged-fluids=" .. formatInteger(sumValues(context.readRefillFluids())))
    output("  refill-entangler-output=" .. tostring(checked(
      "read automatic-refill/entangler output",
      context.refillLinkRedstone.getOutput,
      config.refill.entanglerToggleSide
    )))
    local entanglerActive, activitySignal = context.readEntanglerActivity()
    output("  refill-entangler-activity=" .. (entanglerActive and "running" or "idle")
      .. " signal=" .. tostring(activitySignal)
      .. " threshold=" .. tostring(config.refill.activityThreshold))
    local activeSources = {}
    for _, entry in ipairs(config.fluids) do
      local route = context.refillRoutes[entry.source]
      local value = tonumber(checked(
        "read refill source " .. entry.source,
        route.device.getOutput,
        route.side
      )) or 0
      if value ~= config.refill.disconnectSignal then
        activeSources[#activeSources + 1] = entry.source .. "=" .. value
      end
    end
    output("  active-refill-sources="
      .. (#activeSources > 0 and table.concat(activeSources, ",") or "none"))
  end
  output("  nodes=" .. #context.nodes)
  output("  baseline-field-strength=" .. formatInteger(context.baselineFieldStrength))
  local currentStored = context.getStoredCondensate()
  output("  current-condensate-stock=" .. formatInteger(sumValues(currentStored)))
  context.assertBaselineIsSafe(currentStored)
  context.assertBaselineStockPresent(currentStored)
  local snapshot = context.readNetwork()
  output("  material-cache-items=" .. formatInteger(snapshot.itemTotal))
  output("  material-cache-fluids=" .. formatInteger(snapshot.fluidTotal))
  output("  item-cache-items=" .. formatInteger(context.readItemCacheTotal()))
  output("  fluid-cache-fluids=" .. formatInteger(context.readFluidCacheTotal()))
  if context.hasCompleteOrder(snapshot) then
    local count, fingerprint, divisor = context.getOrderCount(snapshot.items)
    output(string.format("  pending-order=%d fingerprint=%s divisor=%d", count, fingerprint, divisor))
    output("  required-condensate=" .. context.deficitText(context.getRequiredCondensate(snapshot.fluids)))
  end
  output("Configuration OK (read-only check)")
end

return M
