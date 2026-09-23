local M = {}

local function defaultIsInteger(value)
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function read(path, isInteger)
  local handle, reason = io.open(path, "r")
  if not handle then return nil, "missing", reason end

  local contents = handle:read("*a")
  handle:close()
  local text = contents and contents:match("^BEC_PROCESSED_V1 (%d+)\n$")
  local value = tonumber(text)
  if not isInteger(value) then
    return nil, "invalid", "invalid counter contents"
  end
  return value
end

local function write(path, contents)
  local handle, reason = io.open(path, "w")
  if not handle then return nil, reason end

  local wrote, writeReason = handle:write(contents)
  if not wrote then
    pcall(handle.close, handle)
    return nil, writeReason
  end

  local flushed, flushReason = handle:flush()
  if not flushed then
    pcall(handle.close, handle)
    return nil, flushReason
  end

  local closed, closeReason = pcall(handle.close, handle)
  if not closed then return nil, closeReason end
  return true
end

function M.new(options)
  options = options or {}
  local path = assert(options.path, "counter requires a path")
  local isInteger = options.isInteger or defaultIsInteger
  local formatInteger = options.formatInteger or tostring
  local log = options.log or function() end
  local update = options.update or function() end
  local value = 0

  local counter = {}

  function counter:load()
    local primary, primaryState, primaryReason = read(path, isInteger)
    local backup, backupState, backupReason = read(path .. ".bak", isInteger)

    if primary ~= nil or backup ~= nil then
      value = math.max(primary or 0, backup or 0)
      if primaryState == "invalid" or backupState == "invalid" then
        log("WARN", "recovered processed recipe total from the valid counter copy")
      end
    elseif primaryState == "missing" and backupState == "missing" then
      value = 0
    else
      error(string.format(
        "processed recipe counter is unreadable: primary=%s backup=%s",
        tostring(primaryReason),
        tostring(backupReason)
      ), 0)
    end

    update(value)
    log("INFO", "processed recipe total=" .. formatInteger(value))
    return value
  end

  function counter:save(nextValue)
    if not isInteger(nextValue) then
      return nil, "counter value must be a non-negative integer"
    end

    value = nextValue
    local contents = string.format("BEC_PROCESSED_V1 %.0f\n", value)
    local primary = read(path, isInteger)
    local backup = read(path .. ".bak", isInteger)
    local firstPath = path
    local secondPath = path .. ".bak"

    if (backup or -1) < (primary or -1) then
      firstPath, secondPath = secondPath, firstPath
    end

    local firstOk, firstReason = write(firstPath, contents)
    if not firstOk then return nil, firstPath .. ": " .. tostring(firstReason) end

    local secondOk, secondReason = write(secondPath, contents)
    if not secondOk then
      return true, secondPath .. " write failed; the other counter copy is current: "
        .. tostring(secondReason)
    end
    return true
  end

  function counter:get()
    return value
  end

  return counter
end

return M
