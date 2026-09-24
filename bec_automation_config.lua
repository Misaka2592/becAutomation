local loaded, values = pcall(function()
  return require("bec_config").load("bec.conf").automation
end)
if not loaded then
  error("cannot load bec.conf: " .. tostring(values), 0)
end
if type(values) ~= "table" then error("bec.conf is missing the automation section", 0) end
return values