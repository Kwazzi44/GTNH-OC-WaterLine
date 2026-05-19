local filesystem = require("filesystem")
local registry = {}

local registryPath = "/home/registry.lua"

function registry.load()
  if filesystem.exists(registryPath) then
    local ok, res = pcall(function()
      local f = loadfile(registryPath)
      if f then return f() end
    end)
    if ok and type(res) == "table" then
      -- Guarantee all keys exist
      if not res.lineController then res.lineController = {} end
      if not res.controllers then res.controllers = {} end
      for i = 3, 8 do
        local tkey = "t" .. i
        if not res.controllers[tkey] then res.controllers[tkey] = {} end
      end
      return res
    end
  end
  
  -- Return default structure
  local defaultReg = {
    lineController = { machineAddress = nil },
    controllers = {}
  }
  for i = 3, 8 do
    defaultReg.controllers["t" .. i] = { enable = false }
  end
  return defaultReg
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
