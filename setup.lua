local internet = require("internet")
local filesystem = require("filesystem")

local repository = "Misaka2592/becAutomation"
local branch = "main"
local baseUrl = "https://raw.githubusercontent.com/" .. repository .. "/" .. branch .. "/"
local destination = ... or "/home"

local files = {
  "bec_automation.lua",
  "bec_automation_config.lua",
  "bec_component_resolver.lua",
  "bec_counter.lua",
  "bec_dashboard.lua",
  "bec_diagnostics.lua",
  "bec_field_strength.lua",
  "bec_fluid_routes.lua",
  "bec_nanite_transfer.lua",
  "bec_route_mapper.lua",
  "bec_route_mapper_config.lua",
}

local function download(relativePath, index)
  local targetPath = filesystem.concat(destination, relativePath)
  local parentPath = filesystem.path(targetPath)
  if parentPath and not filesystem.isDirectory(parentPath) then
    filesystem.makeDirectory(parentPath)
  end

  local response, reason = internet.request(baseUrl .. relativePath)
  if not response then
    error("download failed for " .. relativePath .. ": " .. tostring(reason), 0)
  end

  local handle, openReason = io.open(targetPath, "wb")
  if not handle then
    error("cannot open " .. targetPath .. ": " .. tostring(openReason), 0)
  end

  local ok, writeReason = pcall(function()
    for chunk in response do
      local wrote, reason = handle:write(chunk)
      if not wrote then error(reason or "write failed", 0) end
    end
  end)
  handle:close()
  if not ok then
    error("cannot write " .. targetPath .. ": " .. tostring(writeReason), 0)
  end

  print(string.format("[%d/%d] %s", index, #files, relativePath))
end

if not filesystem.isDirectory(destination) then
  filesystem.makeDirectory(destination)
end

print("Downloading " .. repository .. " (" .. branch .. ") to " .. destination)
for index, relativePath in ipairs(files) do
  download(relativePath, index)
end
print("Download complete")
