local event = require("event")
local componentDiscoverLib = require("lib.component-discover-lib")

local lineController = {}

function lineController:newFormConfig(config)
  return self:new(config or {})
end

function lineController:new(config)
  local obj = {}

  obj.config = config
  obj.controllerProxy = nil
  local lastWorkProgress = 0

  function obj:init()
    self:findMachineProxy()
  end

  function obj:findMachineProxy()
    local lineCfg = self.config.lineController or self.config
    local machineName = lineCfg.machineName or "multimachine.purificationplant"
    self.controllerProxy = componentDiscoverLib.discoverGtMachine(machineName, lineCfg.machineAddress)

    if self.controllerProxy == nil then
      error("[Line] Water Purification Plant not found")
    end
  end

  function obj:loop()
    local workProgress = self.controllerProxy.getWorkProgress()

    if lastWorkProgress > workProgress or (self.controllerProxy.hasWork() == false and lastWorkProgress ~= 0) then
      event.push("cycle_end")
      lastWorkProgress = 0
    end

    if self.controllerProxy.hasWork() then 
      lastWorkProgress = workProgress
    end
  end

  function obj:getState()
    if self.controllerProxy == nil then
      return "nil"
    end

    if self.controllerProxy.hasWork() then
      return tostring(math.ceil(self.controllerProxy.getWorkProgress() / 20)).."/"..tostring(math.ceil(self.controllerProxy.getWorkMaxProgress()/20))
    end

    return "Disabled"
  end

  function obj:disable()
    if self.controllerProxy ~= nil then
      self.controllerProxy.setWorkAllowed(false)
    end
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return lineController