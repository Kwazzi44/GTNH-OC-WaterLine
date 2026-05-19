local sides = require("sides")
local event = require("event")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")
local gtSensorParserLib = require("lib.gt-sensor-parser")

local t3controller = {}

function t3controller:newFormConfig(config)
  return self:new(config.transposerAddress)
end

function t3controller:new(transposerAddress)
  local obj = {}

  obj.transposerProxy = nil
  obj.controllerProxy = nil

  obj.stateMachine = stateMachineLib:new()
  obj.gtSensorParser = nil

  obj.transposerLiquids = {}

  obj.requiredCount = 900000;

  function obj:init()
    self:findMachineProxy()
    self:findTransposerFluid(self.transposerProxy, "polyaluminiumchloride")

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.update = function()
      if self.controllerProxy.hasWork() then
        self.stateMachine:setState(self.stateMachine.states.work)
      end
    end

    self.stateMachine.states.work = self.stateMachine:createState("Work")
    self.stateMachine.states.work.init = function()
      local currentCount = self.gtSensorParser:getNumber(4, "Polyaluminium Chloride consumed this cycle: §c")

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

    event.listen("cycle_end", function ()
      if self.stateMachine.currentState == self.stateMachine.states.waitEnd then
        self.stateMachine:setState(self.stateMachine.states.idle)
      end
    end)

    self.stateMachine:setState(self.stateMachine.states.idle)
  end

  function obj:findMachineProxy()
    self.controllerProxy = componentDiscoverLib.discoverGtMachine("multimachine.purificationunitflocculator")

    if self.controllerProxy == nil then
      error("[T3] Flocculation Purification Unit not found")
    end

    self.transposerProxy = componentDiscoverLib.discoverProxy(transposerAddress, "[T3] Transposer", "transposer")
    self.gtSensorParser = gtSensorParserLib:new(self.controllerProxy)
  end

  function obj:findTransposerFluid(proxy, fluidName)
    local result, skipped = componentDiscoverLib.discoverTransposerFluidStorage(proxy, {fluidName}, {sides.up})

    if #skipped ~= 0 then
      error("[T4] Can't find liquid: "..table.concat(skipped, ", "))
    end

    for key, value in pairs(result) do
      self.transposerLiquids[key] = value
    end
  end

  function obj:loop()
    self.gtSensorParser:getInformation()
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
    local successChange = self.gtSensorParser:getNumber(2, "Success chance:")

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