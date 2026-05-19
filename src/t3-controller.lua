local sides = require("sides")
local event = require("event")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")
local gtSensorParserLib = require("lib.gt-sensor-parser")
local cycleEndLib = require("lib.cycle-end-lib")
local controllerInitLib = require("lib.controller-init-lib")

local t3controller = {}

function t3controller:newFormConfig(config)
  return self:new(config)
end

function t3controller:new(config)
  local obj = {}

  obj.config = config
  obj.transposerProxy = nil
  obj.controllerProxy = nil

  obj.stateMachine = stateMachineLib:new()
  obj.gtSensorParser = nil

  obj.transposerLiquids = {}
  obj._hadWorkDuringCycle = false

  obj.requiredCount = config.requiredCount or 900000

  function obj:_initBody()
    self:findMachineProxy()
    coroutine.yield()
    self:findTransposerFluid(self.transposerProxy, "polyaluminiumchloride")
    coroutine.yield()

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.update = function()
      if self.controllerProxy.hasWork() then
        self.stateMachine:setState(self.stateMachine.states.work)
      end
    end

    self.stateMachine.states.work = self.stateMachine:createState("Work")
    self.stateMachine.states.work.init = function()
      local currentCount = self.gtSensorParser:getNumber(4, "Polyaluminium Chloride consumed this cycle:",
        nil, { "Polyaluminium Chloride consumed this cycle: " })

      if currentCount ~= nil and currentCount >= self.requiredCount then
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
        return
      end

      local fluidInTank = self.transposerProxy.getFluidInTank(
        self.transposerLiquids["polyaluminiumchloride"].side,
        self.transposerLiquids["polyaluminiumchloride"].tank
      )

      local countToAdd = self.requiredCount

      if fluidInTank.amount < self.requiredCount then
        self.controllerProxy.setWorkAllowed(false)
        event.push("log_warning", "[T3] Not enough Polyaluminium Chloride for craft")

        countToAdd = fluidInTank.amount - (fluidInTank.amount % 100000)
      end

      if countToAdd <= 0 then
        self.stateMachine:setState(self.stateMachine.states.idle)
        return
      end

      local _, result = self.transposerProxy.transferFluid(
        self.transposerLiquids["polyaluminiumchloride"].side,
        sides.up,
        countToAdd,
        self.transposerLiquids["polyaluminiumchloride"].tank
      )

      if result ~= countToAdd then
        event.push("log_warning", "[T3] Fluid transfer error")
      end

      self.stateMachine:setState(self.stateMachine.states.waitEnd)
    end

    self.stateMachine.states.waitEnd = self.stateMachine:createState("Wait End")

    cycleEndLib.register(self, function()
      if self.stateMachine.currentState == self.stateMachine.states.waitEnd then
        self.stateMachine:setState(self.stateMachine.states.idle)
      end
    end)

    self.stateMachine:setState(self.stateMachine.states.idle)
  end

  function obj:init()
    local ok, err = controllerInitLib.runSync(self)
    if not ok then
      error(tostring(err))
    end
  end

  function obj:shutdown()
    cycleEndLib.unregister(self)
  end

  function obj:findMachineProxy()
    local machineName = self.config.machineName or "multimachine.purificationunitflocculator"
    self.controllerProxy = componentDiscoverLib.discoverGtMachine(machineName, self.config.machineAddress)

    if self.controllerProxy == nil then
      error("[T3] Flocculation Purification Unit not found")
    end

    self.transposerProxy = componentDiscoverLib.discoverProxy(self.config.transposerAddress, "[T3] Transposer", "transposer")
    self.gtSensorParser = gtSensorParserLib:new(self.controllerProxy)
  end

  function obj:findTransposerFluid(proxy, fluidName)
    local result, skipped = componentDiscoverLib.discoverTransposerFluidStorage(proxy, {fluidName}, {sides.up})

    if #skipped ~= 0 then
      error("[T3] Can't find liquid: "..table.concat(skipped, ", "))
    end

    for key, value in pairs(result) do
      self.transposerLiquids[key] = value
    end
  end

  function obj:checkLocalCycleEnd()
    local hasWork = self.controllerProxy.hasWork()
    if self.stateMachine.currentState == self.stateMachine.states.waitEnd
        and self._hadWorkDuringCycle and not hasWork then
      self.stateMachine:setState(self.stateMachine.states.idle)
    end
    self._hadWorkDuringCycle = hasWork
  end

  function obj:loop()
    self:checkLocalCycleEnd()
    if self.controllerProxy.hasWork() then
      self.gtSensorParser:getInformation()
    end
    self.stateMachine:update()
  end

  function obj:getState()
    if self.controllerProxy.isWorkAllowed() == false then
      return "Controller disabled"
    end

    if self.controllerProxy.hasWork() == false then
      return "Wait cycle"
    end

    local state = self.stateMachine.currentState and self.stateMachine.currentState.name or "nil"
    local successChange = self.gtSensorParser:getNumber(2, "Success chance:", nil, { "Success:", "chance:" })

    if successChange == nil then
      successChange = 0
    end

    return "State: ["..state.."] Success: ["..successChange.."%]"
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return t3controller