local internet = require("internet")
local filesystem = require("filesystem")

local function loadSetup()
  local handle, reason = io.open("setup.conf", "r")
  if not handle then error("cannot open setup.conf: " .. tostring(reason), 0) end
  local result = {}
  local loader = loadstring or load
  for line in handle:lines() do
    local name, _, value = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
    if name then
      local chunk, compileReason = loader("return " .. value)
      if not chunk then error("invalid setup.conf value: " .. tostring(compileReason), 0) end
      result[name] = chunk()
    end
  end
  handle:close()
  return result
end

local setup = loadSetup()
local repository = setup.repository
local branch = setup.branch
local baseUrl = setup.baseUrl .. repository .. "/" .. branch .. "/"
local destination = ... or setup.destination
local files = setup.files

local function download(relativePath, index)
  local targetPath = filesystem.concat(destination, relativePath)
  local parentPath = filesystem.path(targetPath)
  if parentPath and not filesystem.isDirectory(parentPath) then filesystem.makeDirectory(parentPath) end
  local response, reason = internet.request(baseUrl .. relativePath)
  if not response then error("download failed for " .. relativePath .. ": " .. tostring(reason), 0) end
  local handle, openReason = io.open(targetPath, "wb")
  if not handle then error("cannot open " .. targetPath .. ": " .. tostring(openReason), 0) end
  local ok, writeReason = pcall(function()
    for chunk in response do
      local wrote, chunkReason = handle:write(chunk)
      if not wrote then error(chunkReason or "write failed", 0) end
    end
  end)
  handle:close()
  if not ok then error("cannot write " .. targetPath .. ": " .. tostring(writeReason), 0) end
  print(string.format("[%d/%d] %s", index, #files, relativePath))
end

if not filesystem.isDirectory(destination) then filesystem.makeDirectory(destination) end
print("Downloading " .. repository .. " (" .. branch .. ") to " .. destination)
for index, relativePath in ipairs(files) do download(relativePath, index) end
print("Download complete")
