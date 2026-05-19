local filesystem = require("filesystem")
local registry = {}

local registryPath = "/home/registry_data.lua"
local oldRegistryPath = "/home/registry.lua"

function registry.load()
  local data = nil

  -- 1. Try to load from the new path
  if filesystem.exists(registryPath) then
    local ok, res = pcall(function()
      local f = loadfile(registryPath)
      if f then return f() end
    end)
    if ok and type(res) == "table" and not res.load and not res.save then
      data = res
    end
  end

  -- 2. If new path not found/invalid, try migrating from the old path
  if not data and filesystem.exists(oldRegistryPath) then
    local ok, res = pcall(function()
      local f = loadfile(oldRegistryPath)
      if f then return f() end
    end)
    -- Verify this is the actual raw config table (not the registry module code)
    if ok and type(res) == "table" and not res.load and not res.save then
      data = res
      -- Auto-migrate to the new path immediately
      registry.save(data)
    end
  end
  
  -- 3. Fallback to default structure
  if not data then
    data = {
      lineController = { machineAddress = nil },
      controllers = {}
    }
    for i = 3, 8 do
      data.controllers["t" .. i] = { enable = false }
    end
  end

  -- Ensure all properties exist
  if not data.lineController then data.lineController = {} end
  if not data.controllers then data.controllers = {} end
  for i = 3, 8 do
    local tkey = "t" .. i
    if not data.controllers[tkey] then data.controllers[tkey] = {} end
  end

  return data
end

function registry.save(reg)
  local f = io.open(registryPath, "w")
  if f then
    f:write("return {\n")
    f:write("  lineController = {\n")
    f:write(string.format("    machineAddress = %s,\n", reg.lineController.machineAddress and string.format("%q", reg.lineController.machineAddress) or "nil"))
    f:write("  },\n")
    f:write("  controllers = {\n")
    for i = 3, 8 do
      local tkey = "t" .. i
      local tdata = reg.controllers[tkey] or {}
      f:write(string.format("    %s = {\n", tkey))
      f:write(string.format("      enable = %s,\n", tostring(tdata.enable == true)))
      for k, v in pairs(tdata) do
        if k ~= "enable" then
          f:write(string.format("      %s = %s,\n", k, v and string.format("%q", v) or "nil"))
        end
      end
      f:write("    },\n")
    end
    f:write("  }\n")
    f:write("}\n")
    f:close()
    return true
  end
  return false
end

return registry
