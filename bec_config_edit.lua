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

local function literal(input)
  if input == "!clear" then return "\"\"" end
  if input:match("^%s*[{\"'%d%-]") or input == "true" or input == "false" or input == "nil" then
    return input
  end
  return string.format("%q", input)
end

local lines, entries = readAll()
for index, entry in ipairs(entries) do
  print(string.format("[%d/%d] %s | %s | %s", index, #entries, entry.name, entry.label, entry.value))
  io.write("new value (Enter keeps current, !clear empties): ")
  local input = io.read()
  if input == nil then break end
  if input ~= "" then lines[entry.line] = entry.name .. "\t" .. entry.label .. "\t" .. literal(input) end
end

local temporary = path .. ".tmp"
local handle, reason = io.open(temporary, "w")
if not handle then error("cannot write " .. temporary .. ": " .. tostring(reason), 0) end
for _, line in ipairs(lines) do handle:write(line, "\n") end
handle:close()
local ok, renameReason = os.rename(temporary, path)
if not ok then os.remove(temporary); error("cannot replace " .. path .. ": " .. tostring(renameReason), 0) end
print("configuration updated: " .. path)
