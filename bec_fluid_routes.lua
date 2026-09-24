local configLoader = require("bec_config")
local all = configLoader.load("bec.conf")
local routePath = (all.routeMapper or {}).outputFile or "bec_fluid_routes.conf"
local loaded, routes = pcall(function() return configLoader.load(routePath) end)
if not loaded then error("cannot load " .. tostring(routePath) .. ": " .. tostring(routes), 0) end
return routes
