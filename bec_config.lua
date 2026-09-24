local M = {}

local componentSides = require("sides")
local sides = {
  north = componentSides.north,
  south = componentSides.south,
  east = componentSides.east,
  west = componentSides.west,
  up = componentSides.up,
  down = componentSides.down,
}
sides.default = sides.north
M.sides = sides

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function parseValue(text, source, lineNumber)
  local loader = loadstring or load
  local chunk, reason = loader("return " .. text, source .. ":" .. lineNumber)
  if not chunk then error("invalid value at " .. source .. ":" .. lineNumber .. ": " .. reason, 0) end
  local ok, value = pcall(chunk)
  if not ok then error("cannot evaluate value at " .. source .. ":" .. lineNumber .. ": " .. value, 0) end
  return value
end

local function isSideKey(key)
  return key == "side" or key:sub(-4) == "Side"
end

local function normalize(value, key)
  if type(value) == "table" then
    for childKey, childValue in pairs(value) do
      value[childKey] = normalize(childValue, tostring(childKey))
    end
    return value
  end
  if isSideKey(key) and type(value) == "string" then
    local name = trim(value):lower()
    if name == "" then return sides.default end
    return sides[name] or sides.default
  end
  return value
end

local function setPath(root, path, value)
  local current = root
  local parts = {}
  for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
  if #parts == 0 then error("empty configuration name", 0) end
  for index = 1, #parts - 1 do
    local part = parts[index]
    if type(current[part]) ~= "table" then current[part] = {} end
    current = current[part]
  end
  current[parts[#parts]] = normalize(value, parts[#parts])
end

function M.load(path)
  local handle, reason = io.open(path, "r")
  if not handle and path:sub(1, 1) ~= "/" then
    local source = debug.getinfo(1, "S").source or ""
    local directory = source:sub(1, 1) == "@" and source:sub(2):match("^(.*[/\\])") or nil
    if directory then handle, reason = io.open(directory .. path, "r") end
  end
  if not handle then error("cannot open configuration " .. tostring(path) .. ": " .. tostring(reason), 0) end
  local result = {}
  local lineNumber = 0
  for line in handle:lines() do
    lineNumber = lineNumber + 1
    if not line:match("^%s*#") and trim(line) ~= "" then
      local name, label, raw = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
      if not name then
        handle:close()
        error("configuration line " .. lineNumber .. " must contain name, label and value", 0)
      end
      setPath(result, trim(name), parseValue(trim(raw), path, lineNumber))
    end
  end
  handle:close()
  return result
end

return M
