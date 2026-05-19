local sides = require("sides")
local event = require("event")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")
local gtSensorParserLib = require("lib.gt-sensor-parser")
local cycleEndLib = require("lib.cycle-end-lib")
local controllerInitLib = require("lib.controller-init-lib")

local t6controller = {}

function t6controller:newFormConfig(config)
  return self:new(config)
end

function t6controller:new(config)
  local obj = {}

  obj.config = config
  obj.transposerProxy = nil
  obj.controllerProxy = nil

  obj.stateMachine = stateMachineLib:new()
  obj.gtSensorParser = nil

  obj.transposerItems = {}
  obj._hadWorkDuringCycle = false

  function obj:_initBody()
    self:findMachineProxy()
    coroutine.yield()
    self:resetLenses()
    coroutine.yield()
    self:findTransposerItem(self.transposerProxy, {
      "Orundum Lens",
      "Amber Lens",
      "Aer Lens",
      "Emerald Lens",
      "Mana Diamond Lens",
      "Blue Topaz Lens",
      "Amethyst Lens",
      "Fluor-Buergerite Lens",
      "Dilithium Lens"
    })
    coroutine.yield()

    self.gtSensorParser:getInformation()

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.init = function ()
      if self.stateMachine.data.currentLens ~= nil then
        self.transposerProxy.transferItem(
          sides.bottom, 
          self.transposerItems[self.stateMachine.data.currentLens].side,
          1,
          1,
          self.transposerItems[self.stateMachine.data.currentLens].slot)
      end
    end
    self.stateMachine.states.idle.update = function()
      if self.controllerProxy.hasWork() then
        self.stateMachine:setState(self.stateMachine.states.changeLens)
      end
    end

    self.stateMachine.states.changeLens = self.stateMachine:createState("Change Lens")
    self.stateMachine.states.changeLens.init = function()
      local lens = self.gtSensorParser:getString(5, "Current lens requested: ", nil, { "lens requested:", "Lens:" })
      local recipeError = self.gtSensorParser:getString(6, "Removed lens", nil, { "Failing this recipe", "too early" })

      if lens == nil or (recipeError and recipeError:find("Removed lens")) then
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
        return
      end

      self:putLens(lens)
    end

    self.stateMachine.states.waitLens = self.stateMachine:createState("Wait Lens")
    self.stateMachine.states.waitLens.update = function()
      local lens = self.gtSensorParser:getString(5, "Current lens requested: ", nil, { "lens requested:", "Lens:" })

      if self.controllerProxy.hasWork() == false then
        self.stateMachine:setState(self.stateMachine.states.idle)
        return
      end

      if self.stateMachine.data.currentLens ~= lens then
        self.stateMachine:setState(self.stateMachine.states.changeLens)
      end
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
    if not ok then error(tostring(err)) end
  end

  function obj:shutdown()
    cycleEndLib.unregister(self)
  end

  function obj:findMachineProxy()
    local machineName = self.config.machineName or "multimachine.purificationunituvtreatment"
    self.controllerProxy = componentDiscoverLib.discoverGtMachine(machineName, self.config.machineAddress)

    if self.controllerProxy == nil then
      error("[T6] High Energy Laser Purification Unit not found")
    end

    self.transposerProxy = componentDiscoverLib.discoverProxy(self.config.transposerAddress, "[T6] Transposer", "transposer")
    self.gtSensorParser = gtSensorParserLib:new(self.controllerProxy)
  end

  function obj:findTransposerItem(proxy, itemLabels)
    local result, skipped = componentDiscoverLib.discoverTransposerItemStorage(proxy, itemLabels)

    if #skipped ~= 0 then
      if not (#skipped == 1 and skipped[1] == "Dilithium Lens") then
        error("[T6] Can't find items: "..table.concat(skipped, ", "))
      end
    end

    for key, value in pairs(result) do
      self.transposerItems[key] = value
    end
  end

  function obj:resetLenses()
    local transposerSides = componentDiscoverLib.discoverTransposerItemStorageSide(self.transposerProxy, {sides.bottom})

    if transposerSides[1] ~= nil then
      self.transposerProxy.transferItem(sides.bottom, transposerSides[1], 1)
    end
  end

  function obj:putLens(lens)
    if self.stateMachine.data.currentLens ~= nil then
      self.transposerProxy.transferItem(
        sides.bottom,
        self.transposerItems[self.stateMachine.data.currentLens].side,
        1,
        1,
        self.transposerItems[self.stateMachine.data.currentLens].slot)
    end

    if lens == "Dilithium Lens" and self.transposerItems[lens] == nil then
      self.stateMachine.data.currentLens = nil
      self.stateMachine:setState(self.stateMachine.states.waitEnd)
      return
    end

    local result = self.transposerProxy.transferItem(
      self.transposerItems[lens].side,
      sides.bottom,
      1,
      self.transposerItems[lens].slot)

    if result ~= 1 then
      self.controllerProxy.setWorkAllowed(false)
      self.stateMachine.data.currentLens = nil
      self.stateMachine:setState(self.stateMachine.states.waitEnd)
      event.push("log_warning", "[T6] Invalid slot: "..self.transposerItems[lens].slot.." for: "..lens)
      return
    end

    self.stateMachine.data.currentLens = lens

    if lens == "Dilithium Lens" then
      self.stateMachine:setState(self.stateMachine.states.waitEnd)
    else
      self.stateMachine:setState(self.stateMachine.states.waitLens)
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

return t6controller