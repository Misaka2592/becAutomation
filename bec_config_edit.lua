-- Console editor for the tab-separated BEC hardware configuration format.
local path = ... or "bec.conf"
local editable = {
  ["automation.storageAddress"] = true,
  ["automation.gateAddress"] = true,
  ["automation.cacheInterfaceAddress"] = true,
  ["automation.cacheInterfaceType"] = true,
  ["automation.buffers"] = true,
  ["automation.redstone"] = true,
  ["automation.nanite"] = true,
  ["automation.refill"] = true,
  ["routeMapper.referenceInterfaceAddress"] = true,
  ["routeMapper.redstoneAddresses"] = true,
  ["routeMapper.testSides"] = true,
}

local fieldLabels = {
  ["automation.buffers"] = {
    itemInterfaceAddress = "物品缓存接口地址",
    fluidInterfaceAddress = "流体缓存接口地址",
    interfaceType = "接口类型",
  },
  ["automation.redstone"] = {
    nodeAddress = "节点输出红石地址",
    generatorAddress = "生成器输出红石地址",
    synthesisAddress = "合成控制红石地址",
    haltAddress = "停止控制红石地址",
    nodeToggleSide = "节点输出方向",
    generatorToggleSide = "生成器输出方向",
    synthesisSide = "合成控制方向",
    haltSide = "停止控制方向",
  },
  ["automation.nanite"] = {
    storageBusAddress = "存储总线地址",
    inputSide = "存储总线输入方向",
    ejectRedstoneAddress = "回收红石地址",
    ejectSide = "回收红石方向",
    transposerAddress = "转运器地址",
    targetSide = "转运器目标方向",
    targetOutputSlot = "转运器目标槽位",
  },
  ["automation.refill"] = {
    routeModule = "路由模块",
    cacheInterfaceAddress = "补货缓存接口地址",
    cacheInterfaceType = "补货缓存接口类型",
    entanglerAddress = "纠缠装置控制红石地址",
    entanglerToggleSide = "纠缠装置控制方向",
    activityAddress = "活动信号地址",
    activitySide = "活动信号方向",
  },
}

local fieldOrder = {
  ["automation.buffers"] = {
    "itemInterfaceAddress", "fluidInterfaceAddress", "interfaceType",
  },
  ["automation.redstone"] = {
    "nodeAddress", "generatorAddress", "synthesisAddress", "haltAddress",
    "nodeToggleSide", "generatorToggleSide", "synthesisSide", "haltSide",
  },
  ["automation.nanite"] = {
    "storageBusAddress", "inputSide", "ejectRedstoneAddress", "ejectSide",
    "transposerAddress", "targetSide", "targetOutputSlot",
  },
  ["automation.refill"] = {
    "routeModule", "cacheInterfaceAddress", "cacheInterfaceType",
    "entanglerAddress", "entanglerToggleSide", "activityAddress", "activitySide",
  },
}

local function readAll()
  local handle, reason = io.open(path, "r")
  if not handle then error("cannot open " .. path .. ": " .. tostring(reason), 0) end
  local lines, entries = {}, {}
  for line in handle:lines() do
    lines[#lines + 1] = line
    local name, label, value = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
    if name and editable[name] then
      entries[#entries + 1] = { line = #lines, name = name, label = label, value = value }
    end
  end
  handle:close()
  return lines, entries
end

local function parseValue(text, source, lineNumber)
  local loader = loadstring or load
  local chunk, reason = loader("return " .. text, source .. ":" .. tostring(lineNumber))
  if not chunk then error("invalid value at " .. source .. ":" .. tostring(lineNumber) .. ": " .. reason, 0) end
  local ok, value = pcall(chunk)
  if not ok then error("cannot evaluate value at " .. source .. ":" .. tostring(lineNumber) .. ": " .. value, 0) end
  return value
end

local function literal(input)
  if input == "!clear" then return "\"\"" end
  if input:match("^%s*[{\"'%d%-]") or input == "true" or input == "false" or input == "nil" then
    return input
  end
  return string.format("%q", input)
end

local function serialize(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if value == nil then return "nil" end
  if type(value) ~= "table" then error("cannot serialize " .. type(value), 0) end

  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(left, right)
    if type(left) ~= type(right) then return type(left) == "number" end
    if type(left) == "number" then return left < right end
    return tostring(left) < tostring(right)
  end)

  local parts = {}
  for _, key in ipairs(keys) do
    local field
    if type(key) == "string" and key:match("^[A-Za-z_][A-Za-z0-9_]*$") then
      field = key .. " = "
    else
      field = "[" .. serialize(key) .. "] = "
    end
    parts[#parts + 1] = field .. serialize(value[key])
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function orderedKeys(value, preferred)
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  local ranks = {}
  for index, key in ipairs(preferred or {}) do ranks[key] = index end
  table.sort(keys, function(left, right)
    local leftRank = ranks[left] or math.huge
    local rightRank = ranks[right] or math.huge
    if leftRank ~= rightRank then return leftRank < rightRank end
    if type(left) ~= type(right) then return type(left) == "number" end
    if type(left) == "number" then return left < right end
    return tostring(left) < tostring(right)
  end)
  return keys
end

local function copyPath(pathValue, key)
  local result = {}
  for index, value in ipairs(pathValue) do result[index] = value end
  result[#result + 1] = key
  return result
end

local function pathName(pathValue)
  local parts = {}
  for _, key in ipairs(pathValue) do parts[#parts + 1] = tostring(key) end
  return table.concat(parts, ".")
end

local function fieldLabel(tableName, pathValue)
  local labels = fieldLabels[tableName] or {}
  local fullName = pathName(pathValue)
  if labels[fullName] then return labels[fullName] end
  if #pathValue == 1 and labels[pathValue[1]] then return labels[pathValue[1]] end

  if tableName == "routeMapper.redstoneAddresses" and #pathValue == 1 then
    return "第" .. tostring(pathValue[1]) .. "个流体探测红石接口地址"
  end
  if tableName == "routeMapper.testSides" then
    if #pathValue == 1 then return "第" .. tostring(pathValue[1]) .. "个探测方向" end
    if #pathValue == 2 then
      local suffix = pathValue[2] == "value" and "方向值"
        or pathValue[2] == "name" and "方向名称"
        or tostring(pathValue[2])
      return "第" .. tostring(pathValue[1]) .. "个探测方向的" .. suffix
    end
  end
  return tostring(pathValue[#pathValue])
end

local function collectFields(value, tableName)
  local fields = {}
  local function visit(current, prefix)
    local preferred = #prefix == 0 and fieldOrder[tableName] or nil
    if tableName == "routeMapper.testSides" and #prefix > 0 then
      preferred = { "value", "name" }
    end
    for _, key in ipairs(orderedKeys(current, preferred)) do
      local nextPath = copyPath(prefix, key)
      if type(current[key]) == "table" then
        visit(current[key], nextPath)
      else
        fields[#fields + 1] = {
          path = nextPath,
          name = pathName(nextPath),
          label = fieldLabel(tableName, nextPath),
          value = current[key],
        }
      end
    end
  end
  visit(value, {})
  return fields
end

local function setPath(root, pathValue, value)
  local current = root
  for index = 1, #pathValue - 1 do current = current[pathValue[index]] end
  current[pathValue[#pathValue]] = value
end

local function readNewValue(prompt)
  while true do
    io.write(prompt)
    local input = io.read()
    if input == nil then return nil, false, true end
    if input == "" then return nil, false, false end
    local ok, value = pcall(parseValue, literal(input), "input", 0)
    if ok then return value, true, false end
    print(tostring(value))
  end
end

local lines, entries = readAll()
local stopped = false
for index, entry in ipairs(entries) do
  local parsed, parseReason = pcall(parseValue, entry.value, path, entry.line)
  if not parsed then error(parseReason, 0) end

  if type(parseReason) == "table" then
    print(string.format("[%d/%d] %s\t%s", index, #entries, entry.name, entry.label))
    local fields = collectFields(parseReason, entry.name)
    for fieldIndex, field in ipairs(fields) do
      print(string.format("[%d/%d] %s | %s | %s", fieldIndex, #fields,
        field.name, field.label, serialize(field.value)))
      local newValue, changed, eof = readNewValue("new value (Enter keeps current, !clear empties): ")
      if eof then stopped = true; break end
      if changed then setPath(parseReason, field.path, newValue) end
    end
    lines[entry.line] = entry.name .. "\t" .. entry.label .. "\t" .. serialize(parseReason)
  else
    print(string.format("[%d/%d] %s\t%s", index, #entries, entry.name, entry.label))
    print(string.format("[1/1] value | %s | %s", entry.label, entry.value))
    local newValue, changed, eof = readNewValue("new value (Enter keeps current, !clear empties): ")
    if eof then stopped = true
    elseif changed then lines[entry.line] = entry.name .. "\t" .. entry.label .. "\t" .. serialize(newValue) end
  end
  if stopped then break end
end

local temporary = path .. ".tmp"
local handle, reason = io.open(temporary, "w")
if not handle then error("cannot write " .. temporary .. ": " .. tostring(reason), 0) end
for _, line in ipairs(lines) do handle:write(line, "\n") end
handle:close()
local ok, renameReason = os.rename(temporary, path)
if not ok then os.remove(temporary); error("cannot replace " .. path .. ": " .. tostring(renameReason), 0) end
print("configuration updated: " .. path)
