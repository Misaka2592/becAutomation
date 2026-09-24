local os = require("os")

local M = {}

local function tierOf(value)
  if value == nil or type(value) ~= "table" then return nil end
  local tier = tonumber(value.tier)
  if tier == nil or tier % 1 ~= 0 then return nil end
  return tier
end

local function isNumber(value)
  return type(value) == "number" and value == value
end

function M.new(options)
  options = options or {}
  local config = assert(options.config, "nanite controller requires config")
  local storageBus = assert(options.storageBus, "nanite controller requires storage bus")
  local ejectRedstone = assert(options.ejectRedstone, "nanite controller requires eject redstone")
  local transposer = assert(options.transposer, "nanite controller requires transposer")
  local controllerNodes = options.controllerNodes or {}
  if type(controllerNodes) ~= "table" then
    error("nanite controller requires a controller node list", 0)
  end

  local setFilter = storageBus.setStorageOreFilter or storageBus.setStorage0reFilter
  if type(setFilter) ~= "function" then
    error("me_storagebus does not expose setStorageOreFilter or setStorage0reFilter", 0)
  end

  local function defaultNow()
    return os.clock()
  end

  local self = {
    config = config,
    storageBus = storageBus,
    ejectRedstone = ejectRedstone,
    transposer = transposer,
    controllerNodes = {},
    setFilterMethod = setFilter,
    now = options.now or defaultNow,
    sleep = options.sleep or os.sleep,
    log = options.log or function() end,
    isHalted = options.isHalted,
    stage = "IDLE",
    phase = "IDLE",
    currentFilter = "unknown",
    currentEject = "unknown",
    requiredTier = nil,
    providedTier = nil,
    lastSuppliedTier = nil,
    lastError = nil,
    lastErrorCode = nil,
    op = nil,
    lastRequirementChange = false,
  }

  local poll = assert(tonumber(config.poll), "nanite.poll is required")
  local ejectTimeout = assert(tonumber(config.ejectTimeout), "nanite.ejectTimeout is required")
  local supplyTimeout = assert(tonumber(config.supplyTimeout), "nanite.supplyTimeout is required")
  local activeSignal = assert(config.activeSignal, "nanite.activeSignal is required")
  local inactiveSignal = assert(config.inactiveSignal, "nanite.inactiveSignal is required")

  local function safeLog(level, message)
    pcall(self.log, level, message)
  end

  local function call(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then return false, tostring(a) end
    return true, a, b
  end

  function self:_now()
    local ok, value = pcall(self.now)
    if not ok then error("nanite clock: " .. tostring(value), 0) end
    if not isNumber(value) then error("nanite clock returned a non-number", 0) end
    return value
  end

  function self:_sleep(seconds)
    if seconds <= 0 then return true end
    local ok, reason = pcall(self.sleep, seconds)
    if not ok then error("nanite sleep: " .. tostring(reason), 0) end
    return true
  end

  function self:_setFilter(ore)
    local value = ore or "null"
    local ok, reason = call(self.setFilterMethod, self.config.inputSide, value)
    if not ok then error("set nanite storage-bus filter: " .. reason, 0) end
    self.currentFilter = value
    safeLog("INFO", "nanite storage-bus ore filter -> " .. value)
  end

  function self:_setEject(active)
    local value = active and activeSignal or inactiveSignal
    local ok, reason = call(self.ejectRedstone.setOutput, self.config.ejectSide, value)
    if not ok then error("set nanite eject redstone: " .. reason, 0) end
    self.currentEject = value
  end

  local function nodeLabel(node, index)
    return "control node " .. tostring(index) .. (node.address and (" (" .. node.address .. ")") or "")
  end

  local function readTier(node, index, method, label)
    local ok, value = call(node[method])
    if not ok then error("read " .. label .. " from " .. nodeLabel(node, index) .. ": " .. value, 0) end
    local tier = tierOf(value)
    if value ~= nil and tier == nil then
      error("invalid " .. label .. " from " .. nodeLabel(node, index), 0)
    end
    return value, tier
  end

  function self:setControllerNodes(nodes)
    if type(nodes) ~= "table" then error("nanite controller node list must be a table", 0) end
    self.controllerNodes = {}
    for index, node in ipairs(nodes) do
      if type(node) ~= "table"
          or type(node.getRequiredTier) ~= "function"
          or type(node.getProvidedTier) ~= "function" then
        error("invalid nanite control node at index " .. tostring(index), 0)
      end
      self.controllerNodes[#self.controllerNodes + 1] = node
    end
    self.lastRequirementChange = false
    return true
  end

  function self:clearControllerNodes()
    self.controllerNodes = {}
    self.lastRequirementChange = false
    self.requiredTier = nil
    self.providedTier = nil
    return true
  end

  self:setControllerNodes(controllerNodes)

  function self:_readControllers()
    local states = {}
    self.requiredTier = nil
    self.providedTier = nil
    for index, node in ipairs(self.controllerNodes) do
      local required, requiredTier = readTier(node, index, "getRequiredTier", "nanite required tier")
      local provided, providedTier = readTier(node, index, "getProvidedTier", "nanite provided tier")
      local state = {
        node = node,
        index = index,
        required = required,
        requiredTier = requiredTier,
        provided = provided,
        providedTier = providedTier,
      }
      states[#states + 1] = state
      if requiredTier ~= nil and self.requiredTier == nil then self.requiredTier = requiredTier end
      if providedTier ~= nil and self.providedTier == nil then self.providedTier = providedTier end
    end
    return states
  end

  local function activeStates(states)
    local active = {}
    for _, state in ipairs(states) do
      if state.requiredTier ~= nil then active[#active + 1] = state end
    end
    return active
  end

  local function firstRequiredTier(states)
    for _, state in ipairs(states) do
      if state.requiredTier ~= nil then return state.requiredTier end
    end
    return nil
  end

  local function anyTierMatched(states)
    for _, state in ipairs(states) do
      if state.requiredTier ~= nil and state.requiredTier == state.providedTier then
        return true, state.requiredTier
      end
    end
    return false, nil
  end

  local function allTiersMismatch(states)
    local active = activeStates(states)
    if #active == 0 then return false end
    for _, state in ipairs(active) do
      if state.requiredTier == state.providedTier then return false end
    end
    return true
  end

  function self:_resetHardware()
    self.op = nil
    self.phase = "RESETTING"
    local filterOk, filterReason = pcall(function() self:_setFilter("null") end)
    if not filterOk then self.currentFilter = "unknown" end
    local ejectOk, ejectReason = pcall(function() self:_setEject(false) end)
    if not ejectOk then self.currentEject = "unknown" end
    if not filterOk or not ejectOk then
      self.stage = "ERROR"
      self.phase = "ERROR"
      local reason = {}
      if not filterOk then reason[#reason + 1] = tostring(filterReason) end
      if not ejectOk then reason[#reason + 1] = tostring(ejectReason) end
      return false, table.concat(reason, "; "), "api_error"
    end
    self.stage = "IDLE"
    self.phase = "IDLE"
    return true
  end

  function self:_failure(reason, code)
    code = code or "api_error"
    local resetOk, resetReason = self:_resetHardware()
    local finalReason = tostring(reason)
    if not resetOk then finalReason = finalReason .. "; reset failed: " .. tostring(resetReason) end
    self.stage = "ERROR"
    self.phase = "ERROR"
    self.lastError = finalReason
    self.lastErrorCode = code
    return false, finalReason, code
  end

  function self:_halted()
    if type(self.isHalted) ~= "function" then return false end
    local ok, halted = pcall(self.isHalted)
    if not ok then error("nanite halt callback: " .. tostring(halted), 0) end
    if not halted then return false end
    local resetOk, resetReason, resetCode = self:reset()
    if not resetOk then
      return false, "nanite transfer halted; " .. tostring(resetReason), resetCode or "api_error"
    end
    self.lastError = "nanite transfer halted"
    self.lastErrorCode = "halted"
    return false, self.lastError, "halted"
  end

  function self:reset()
    local ok, reason, code = self:_resetHardware()
    self.lastRequirementChange = false
    if not ok then
      self.lastError = tostring(reason)
      self.lastErrorCode = code or "api_error"
      return false, self.lastError, self.lastErrorCode
    end
    self.lastError = nil
    self.lastErrorCode = nil
    return true
  end

  function self:_startOperation(kind, tier)
    local started = self:_now()
    self:_setFilter("null")
    self.op = {
      kind = kind,
      targetTier = tier,
      phase = "SETTLE",
      phaseAt = started + poll,
      started = started,
      deadline = nil,
    }
    self.phase = "SETTLE"
    self.stage = "CLOSING"
  end

  function self:_startReplacement(tier)
    self:_startOperation("ensure", tier)
  end

  function self:_restartForRequirement(tier)
    self.lastRequirementChange = true
    local ok, reason, code = self:_resetHardware()
    if not ok then return false, reason, code end
    if tier == nil then
      return true, "idle"
    end
    local ore = self.config.oreByTier and self.config.oreByTier[tier]
    if type(ore) ~= "string" or ore == "" then
      return self:_failure("no nanite ore dictionary entry for tier " .. tostring(tier), "unknown_tier")
    end
    self:_startReplacement(tier)
    return nil, "pending"
  end

  function self:_tickOperation()
    local op = self.op
    local now = self:_now()
    if op.phase == "SETTLE" then
      if now < op.phaseAt then return nil, "pending" end
      self:_setEject(true)
      op.phase = "EJECT"
      op.started = now
      op.deadline = now + ejectTimeout
      self.phase = "EJECTING"
      return nil, "pending"
    end

    if op.phase == "EJECT" then
      local stackOk, stack = call(self.transposer.getStackInSlot,
        self.config.targetSide, self.config.targetOutputSlot)
      if not stackOk then error("read nanite output slot: " .. tostring(stack), 0) end
      local empty = stack == nil or tonumber(stack.size or 0) <= 0
      if not empty then
        if now > op.deadline then
          return self:_failure(string.format(
            "nanite output slot did not empty within %.1fs", ejectTimeout), "timeout")
        end
        return nil, "pending"
      end

      self:_setEject(false)
      if op.kind == "eject" then
        self.op = nil
        self.stage = "IDLE"
        self.phase = "IDLE"
        safeLog("INFO", "nanite output slot emptied")
        return true, "idle"
      end

      local ore = self.config.oreByTier and self.config.oreByTier[op.targetTier]
      if type(ore) ~= "string" or ore == "" then
        return self:_failure("no nanite ore dictionary entry for tier " .. tostring(op.targetTier), "unknown_tier")
      end
      self:_setFilter(ore)
      op.phase = "SUPPLY"
      op.started = now
      op.deadline = now + supplyTimeout
      self.phase = "SUPPLYING"
      return nil, "pending"
    end

    if op.phase == "SUPPLY" then
      local states = self:_readControllers()
      local active = activeStates(states)
      local matched, matchedTier = anyTierMatched(states)
      if matched then
        self:_setFilter("null")
        self.op = nil
        self.stage = "IDLE"
        self.phase = "IDLE"
        self.lastSuppliedTier = matchedTier or op.targetTier
        self.lastError = nil
        self.lastErrorCode = nil
        safeLog("INFO", "nanite tier " .. tostring(self.lastSuppliedTier) .. " supplied")
        return true, "ready"
      end
      local currentTier = firstRequiredTier(states)
      if #active == 0 then return self:_restartForRequirement(nil) end
      if currentTier ~= op.targetTier then
        return self:_restartForRequirement(currentTier)
      end
      if now > op.deadline then
        return self:_failure(string.format(
          "nanite tier %d was not supplied within %.1fs", op.targetTier, supplyTimeout), "timeout")
      end
      return nil, "pending"
    end

    return self:_failure("invalid nanite transfer phase", "api_error")
  end

  function self:_tickImpl()
    local halted, haltReason, haltCode = self:_halted()
    if halted == false and haltReason ~= nil then return false, haltReason, haltCode end

    -- A direct eject is independent of the current BEC recipe.  It must keep
    -- progressing even when getRequiredTier() is nil while the machine is
    -- idle.
    if self.op and self.op.kind == "eject" then
      return self:_tickOperation()
    end

    local states = self:_readControllers()
    local active = activeStates(states)
    if #active == 0 then
      local ok, reason, code = self:_resetHardware()
      if not ok then return false, reason, code end
      return true, "idle"
    end
    local requiredTier = firstRequiredTier(states)
    if not (self.config.oreByTier and type(self.config.oreByTier[requiredTier]) == "string"
        and self.config.oreByTier[requiredTier] ~= "") then
      return self:_failure("no nanite ore dictionary entry for tier " .. tostring(requiredTier), "unknown_tier")
    end

    local matched, matchedTier = anyTierMatched(states)
    if matched and self.op then
      if self.currentFilter ~= "null" then self:_setFilter("null") end
      self.op = nil
      self.stage = "IDLE"
      self.phase = "IDLE"
      self.lastSuppliedTier = matchedTier or requiredTier
      return true, "ready"
    end

    if self.op then
      if self.op.targetTier ~= requiredTier then
        local restarted, reason, code = self:_restartForRequirement(requiredTier)
        if restarted == false then return false, reason, code end
        return nil, "pending"
      end
      return self:_tickOperation()
    end

    if matched then
      if self.currentFilter ~= "null" then self:_setFilter("null") end
      self.stage = "IDLE"
      self.phase = "IDLE"
      self.lastSuppliedTier = matchedTier or requiredTier
      return true, "ready"
    end

    if allTiersMismatch(states) then self:_startReplacement(requiredTier) end
    return nil, "pending"
  end

  function self:tick()
    self.lastRequirementChange = false
    local ok, a, b = xpcall(function() return self:_tickImpl() end, debug.traceback)
    if not ok then return self:_failure("nanite transfer API error: " .. tostring(a), "api_error") end
    return a, b, self.lastErrorCode
  end

  local function blockingSleep()
    self:_sleep(poll)
  end

  function self:ensure(required)
    if required == nil then return self:reset() end
    local targetTier = tierOf(required)
    if targetTier == nil then return self:_failure("invalid nanite requirement", "invalid_requirement") end
    local ore = self.config.oreByTier and self.config.oreByTier[targetTier]
    if type(ore) ~= "string" or ore == "" then
      return self:_failure("no nanite ore dictionary entry for tier " .. tostring(targetTier), "unknown_tier")
    end

    local states = self:_readControllers()
    local active = activeStates(states)
    local currentTier = firstRequiredTier(states)
    local matched, matchedTier = anyTierMatched(states)
    if matched then
      if self.currentFilter ~= "null" then self:_setFilter("null") end
      self.lastSuppliedTier = matchedTier or targetTier
      self.lastError = nil
      self.lastErrorCode = nil
      return true
    end
    if #active == 0 or currentTier ~= targetTier then
      return self:_failure("nanite requirement changed before supply", "requirement_changed")
    end

    if self.op and (self.op.kind ~= "ensure" or self.op.targetTier ~= targetTier) then
      local ok, reason, code = self:reset()
      if not ok then return false, reason, code end
    end
    if not self.op then self:_startReplacement(targetTier) end

    local started = self:_now()
    local overallDeadline = started + ejectTimeout + supplyTimeout + poll * 2
    while true do
      local result, reason, code = self:tick()
      if result == true then
        if reason == "ready" then return true end
        return false, "nanite requirement became idle", "requirement_changed"
      end
      if result == false then return false, reason, code end
      if self.lastRequirementChange then
        self.lastRequirementChange = false
        return false, "nanite requirement changed during supply", "requirement_changed"
      end
      if self:_now() > overallDeadline then return self:_failure("nanite transfer timed out", "timeout") end
      blockingSleep()
    end
  end

  function self:ensureCurrent(initial)
    local started = self:_now()
    while true do
      local states = self:_readControllers()
      local active = activeStates(states)
      if #active == 0 then
        if not initial then return self:reset() end
        if self:_now() - started > supplyTimeout then
          return self:_failure("nanite requirement did not become available", "timeout")
        end
        blockingSleep()
      else
        local required = active[1].required
        local ok, reason, code = self:ensure(required)
        if ok then return true end
        if not (initial and code == "requirement_changed") then return false, reason, code end
        if self:_now() - started > supplyTimeout then
          return self:_failure("nanite requirement did not stabilize", "timeout")
        end
      end
    end
  end

  function self:ejectCurrent()
    if self.op and self.op.kind ~= "eject" then
      local ok, reason, code = self:reset()
      if not ok then return false, reason, code end
    end
    if not self.op then self:_startOperation("eject") end
    local started = self:_now()
    local deadline = started + ejectTimeout + poll
    while true do
      local result, reason, code = self:tick()
      if result ~= nil then
        if result then return true end
        return false, reason, code
      end
      if self:_now() > deadline then return self:_failure("nanite eject timed out", "timeout") end
      blockingSleep()
    end
  end

  function self:idle()
    local ok, reason, code = self:reset()
    if not ok then return false, reason, code end
    if config.enableCache then
      if self.lastSuppliedTier == nil then return self:ejectCurrent() end
      local states = self:_readControllers()
      if self.providedTier == self.lastSuppliedTier then return true end
    end
    return self:ejectCurrent()
  end

  function self:getStatus()
    local status = {
      stage = self.stage,
      phase = self.phase,
      filter = self.currentFilter,
      commandedFilter = self.currentFilter,
      filterState = "commanded-only",
      filterVerification = "commanded-only",
      ejectSignal = self.currentEject,
      requiredTier = nil,
      providedTier = nil,
      requiredError = nil,
      providedError = nil,
      controllerNodeCount = #self.controllerNodes,
      matchedNodeCount = 0,
      nodes = {},
      lastError = self.lastError,
      errorCode = self.lastErrorCode,
    }

    for index, node in ipairs(self.controllerNodes) do
      local entry = { index = index, address = node.address, requiredTier = nil, providedTier = nil }
      local requiredOk, required = pcall(node.getRequiredTier)
      if requiredOk then
        entry.requiredTier = tierOf(required)
        if status.requiredTier == nil then status.requiredTier = entry.requiredTier end
      else
        entry.requiredError = tostring(required)
        status.requiredError = status.requiredError or entry.requiredError
      end
      local providedOk, provided = pcall(node.getProvidedTier)
      if providedOk then
        entry.providedTier = tierOf(provided)
        if status.providedTier == nil then status.providedTier = entry.providedTier end
      else
        entry.providedError = tostring(provided)
        status.providedError = status.providedError or entry.providedError
      end
      if entry.requiredTier ~= nil and entry.requiredTier == entry.providedTier then
        status.matchedNodeCount = status.matchedNodeCount + 1
      end
      status.nodes[#status.nodes + 1] = entry
    end
    return status
  end

  -- The non-blocking tick already has its own outer guard.  These blocking
  -- convenience methods also need one because their preflight reads and
  -- injected clock/sleep calls happen outside tick().
  local rawEnsure = self.ensure
  self.ensure = function(controller, required)
    local ok, a, b, c = xpcall(function()
      return rawEnsure(controller, required)
    end, debug.traceback)
    if ok then return a, b, c end
    return controller:_failure("nanite transfer API error: " .. tostring(a), "api_error")
  end

  local rawEnsureCurrent = self.ensureCurrent
  self.ensureCurrent = function(controller, initial)
    local ok, a, b, c = xpcall(function()
      return rawEnsureCurrent(controller, initial)
    end, debug.traceback)
    if ok then return a, b, c end
    return controller:_failure("nanite transfer API error: " .. tostring(a), "api_error")
  end

  local rawEjectCurrent = self.ejectCurrent
  self.ejectCurrent = function(controller)
    local ok, a, b, c = xpcall(function()
      return rawEjectCurrent(controller)
    end, debug.traceback)
    if ok then return a, b, c end
    return controller:_failure("nanite transfer API error: " .. tostring(a), "api_error")
  end

  local rawIdle = self.idle
  self.idle = function(controller)
    local ok, a, b, c = xpcall(function()
      return rawIdle(controller)
    end, debug.traceback)
    if ok then return a, b, c end
    return controller:_failure("nanite transfer API error: " .. tostring(a), "api_error")
  end

  return self
end

return M
