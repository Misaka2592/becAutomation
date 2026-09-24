local internet = require("internet")
local filesystem = require("filesystem")

local repository = "Misaka2592/becAutomation"
local branch = "experiment-configuration"
local version = "0.1.5-conf12"
local configVersion = 12
local essentialsName = "essentials"
local baseUrl = "https://raw.githubusercontent.com/" .. repository .. "/" .. branch .. "/"
local destination = ... or "/home"

local function parseVersion(value)
  local major, minor, patch, schema = tostring(value):match("^(%d+)%.(%d+)%.(%d+)%-conf(%d+)$")
  if not major then error("invalid setup version: " .. tostring(value), 0) end
  return tonumber(major), tonumber(minor), tonumber(patch), tonumber(schema)
end

local _, _, _, versionConfig = parseVersion(version)
if versionConfig ~= configVersion then
  error("setup version and main configuration version do not match", 0)
end

local function compareVersions(left, right)
  local leftMajor, leftMinor, leftPatch, leftSchema = parseVersion(left)
  local rightMajor, rightMinor, rightPatch, rightSchema = parseVersion(right)
  for index, value in ipairs({
    { leftMajor, rightMajor },
    { leftMinor, rightMinor },
    { leftPatch, rightPatch },
    { leftSchema, rightSchema },
  }) do
    if value[1] < value[2] then return -1 end
    if value[1] > value[2] then return 1 end
  end
  return 0
end

local function validateRelativePath(path)
  if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/"
      or path:find("..", 1, true) or path == "setup.lua" then
    error("invalid file path in essentials: " .. tostring(path), 0)
  end
end

local function readEssentials(path)
  local handle, reason = io.open(path, "r")
  if not handle then return nil, reason end
  local metadata = { files = {}, seen = {} }
  local duplicate
  for line in handle:lines() do
    local key, value = line:match("^([%w_]+)=(.-)%s*$")
    if key == "version" then
      metadata.version = value
    elseif key == "configVersion" then
      metadata.configVersion = tonumber(value)
    elseif key == "file" then
      validateRelativePath(value)
      if metadata.seen[value] then
        duplicate = value
      else
        metadata.seen[value] = true
        metadata.files[#metadata.files + 1] = value
      end
    end
  end
  handle:close()
  if duplicate then return nil, "duplicate file entry: " .. duplicate end
  if type(metadata.version) ~= "string" or metadata.version == ""
      or type(metadata.configVersion) ~= "number" or #metadata.files == 0 then
    return nil, "missing version, configVersion or file entries"
  end
  local _, _, _, versionConfig = parseVersion(metadata.version)
  if metadata.configVersion % 1 ~= 0 or metadata.configVersion < 1 then
    return nil, "invalid configVersion"
  end
  if metadata.configVersion ~= versionConfig then
    return nil, "version and configVersion do not match"
  end
  if not metadata.seen[essentialsName] then
    return nil, "essentials is missing from its own file list"
  end
  return metadata
end

local function readConfigVersion(path, pattern)
  local handle = io.open(path, "r")
  if not handle then return nil end
  for line in handle:lines() do
    local value = line:match(pattern)
    if value then
      handle:close()
      return tonumber(value)
    end
  end
  handle:close()
  return nil
end

local function installedConfigVersion()
  return readConfigVersion(
    filesystem.concat(destination, "bec.conf"),
    "^automation%.schemaVersion\t[^\t]*\t(%d+)%s*$"
  ) or readConfigVersion(
    filesystem.concat(destination, "bec_automation_config.lua"),
    "^%s*schemaVersion%s*=%s*(%d+)"
  )
end

local function removePath(relativePath)
  validateRelativePath(relativePath)
  local targetPath = filesystem.concat(destination, relativePath)
  if not filesystem.exists(targetPath) then return end
  local ok, removed, reason = pcall(filesystem.remove, targetPath)
  if not ok or removed == false then
    error("cannot remove " .. targetPath .. ": " .. tostring(reason or removed), 0)
  end
end

local function removeInstalled(metadata)
  for _, relativePath in ipairs(metadata.files) do removePath(relativePath) end
  removePath(essentialsName)
end

local function download(relativePath, index, total)
  validateRelativePath(relativePath)
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
  print(string.format("[%d/%d] %s", index, total, relativePath))
end

local function downloadEssentials()
  download(essentialsName, 1, 1)
  local metadata, reason = readEssentials(filesystem.concat(destination, essentialsName))
  if not metadata then error("downloaded essentials is invalid: " .. tostring(reason), 0) end
  if compareVersions(version, metadata.version) < 0 then
    error("setup.lua is older than the downloaded essentials (" .. metadata.version .. ")", 0)
  end
  return metadata
end

local function installProject()
  local metadata = downloadEssentials()
  local files = {}
  for _, relativePath in ipairs(metadata.files) do
    if relativePath ~= essentialsName then files[#files + 1] = relativePath end
  end
  local total = #files + 1
  for index, relativePath in ipairs(files) do download(relativePath, index + 1, total) end
  print("Download complete: " .. metadata.version)
end

if not filesystem.isDirectory(destination) then filesystem.makeDirectory(destination) end
local essentialsPath = filesystem.concat(destination, essentialsName)
local essentialsExists = filesystem.exists(essentialsPath)
if essentialsExists then
  local metadata, reason = readEssentials(essentialsPath)
  if not metadata then error("cannot read " .. essentialsName .. ": " .. tostring(reason), 0) end
  local comparison = compareVersions(version, metadata.version)
  if comparison < 0 then
    print("setup.lua is older than the installed essentials (" .. metadata.version .. "); installation stopped")
    return
  elseif comparison > 0 then
    print("newer setup detected; removing the previous installation")
    removeInstalled(metadata)
    installProject()
    return
  end
  print("BEC " .. version .. " is already installed; no download required")
  return
end

local installedVersion = installedConfigVersion()
if installedVersion and installedVersion > configVersion then
  print("setup.lua is older than the installed main configuration version " .. installedVersion .. "; installation stopped")
  return
elseif installedVersion and installedVersion < configVersion then
  print("main configuration is older; installing the current project")
  installProject()
elseif installedVersion == configVersion then
  print("essentials is missing but the main configuration is current; downloading essentials only")
  downloadEssentials()
else
  print("no installed configuration found; installing the current project")
  installProject()
end
