local configLoader = require("bec_config")
local routeConfig = require("bec_route_mapper_config")
local loaded, routes = pcall(function() return configLoader.load(routeConfig.outputFile) end)
if not loaded then error("cannot load " .. tostring(routeConfig.outputFile) .. ": " .. tostring(routes), 0) end
return routes
