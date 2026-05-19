local sides = require("sides")
local event = require("event")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")
local gtSensorParserLib = require("lib.gt-sensor-parser")
local cycleEndLib = require("lib.cycle-end-lib")
local controllerInitLib = require("lib.controller-init-lib")

local t8controller = {}

function t8controller:newFormConfig(config)
  return self:new(config)
end

function t8controller:new(config)
  local obj = {}

  obj.config = config
  obj.maxQuarkCount = config.maxQuarkCount or 4

  obj.transposerProxy = nil
  obj.subMeInterfaceProxy = nil
  obj.controllerProxy = nil

  obj.stateMachine = stateMachineLib:new()
  obj.gtSensorParser = nil

  obj.transposerItems = {}
  obj._hadWorkDuringCycle = false
  obj._meCraftQueue = nil
  obj._meCraftCooldown = 4
  obj._meCraftBatchSize = 2

  function obj:_sensorHasYes()
    local line = #self.gtSensorParser.sensorData
    if line < 1 then
      return false
    end
    return self.gtSensorParser:stringHasAny(line, { "Yes", "yes", "YES" }) == true
  end

  function obj:_initBody()
    self:findMachineProxy()
    coroutine.yield()
    self:findTransposerItem(self.transposerProxy, {
      "Up-Quark Releasing Catalyst",
      "Down-Quark Releasing Catalyst",
      "Strange-Quark Releasing Catalyst",
      "Charm-Quark Releasing Catalyst",
      "Bottom-Quark Releasing Catalyst",
      "Top-Quark Releasing Catalyst"
    })
    coroutine.yield()

    self.gtSensorParser:getInformation()

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.update = function()
      if self.controllerProxy.hasWork() then
        if self:_sensorHasYes() then
          self.stateMachine:setState(self.stateMachine.states.waitEnd)
        else
          self.stateMachine:setState(self.stateMachine.states.putFirst)
        end
      end
    end

    self.stateMachine.states.putFirst = self.stateMachine:createState("Put First")
    self.stateMachine.states.putFirst.init = function()
      if self:putQuarks(1) then
        self.stateMachine:setState(self.stateMachine.states.resultPutFirst)
      end
    end

    self.stateMachine.states.resultPutFirst = self.stateMachine:createState("Result Put First")
    self.stateMachine.states.resultPutFirst.update = function()
      if self:_sensorHasYes() then
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
      else
        self.stateMachine:setState(self.stateMachine.states.putSecond)
      end
    end

    self.stateMachine.states.putSecond = self.stateMachine:createState("Put Second")
    self.stateMachine.states.putSecond.init = function()
      if self:putQuarks(2) then
        self.stateMachine:setState(self.stateMachine.states.resultPutSecond)
      end
    end

    self.stateMachine.states.resultPutSecond = self.stateMachine:createState("Result Put Second")
    self.stateMachine.states.resultPutSecond.update = function()
      if self:_sensorHasYes() then
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
      else
        self.stateMachine:setState(self.stateMachine.states.putThird)
      end
    end

    self.stateMachine.states.putThird = self.stateMachine:createState("Put Third")
    self.stateMachine.states.putThird.init = function()
      if self:putQuarks(3) then
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
      end
    end

    self.stateMachine.states.waitEnd = self.stateMachine:createState("Wait End")

    self.stateMachine.states.craftQuarks = self.stateMachine:createState("Craft Quarks")
    
    self.stateMachine.states.craftQuarks.init = function()
      local computer = require("computer")
      -- Засекаем 3 секунды ожидания без блокировки потока
      self.stateMachine.data.craftWaitTime = computer.uptime() + 3
    end
    
    self.stateMachine.states.craftQuarks.update = function()
      local computer = require("computer")
      if computer.uptime() < self.stateMachine.data.craftWaitTime then
        return
      end

      if self._meCraftBusyUntil and computer.uptime() < self._meCraftBusyUntil then
        return
      end

      if not self._meCraftQueue then
        self._meCraftQueue = {}
        local quarks = self.subMeInterfaceProxy.getItemsInNetwork({ name = "gregtech:gt.metaitem.03" })
        for _, quark in pairs(quarks) do
          if quark.label ~= "Unaligned Quark Releasing Catalyst" and quark.size < self.maxQuarkCount then
            table.insert(self._meCraftQueue, quark)
          end
        end
      end

      local processed = 0
      while #self._meCraftQueue > 0 and processed < self._meCraftBatchSize do
        local quark = table.remove(self._meCraftQueue, 1)
        local crafts = self.subMeInterfaceProxy.getCraftables({ label = quark.label })

        if crafts[1] == nil then
          event.push("log_warning", "[T8] No craft for: " .. quark.label)
          self.controllerProxy.setWorkAllowed(false)
        else
          crafts[1].request(self.maxQuarkCount - quark.size)
        end

        processed = processed + 1
      end

      if #self._meCraftQueue > 0 then
        self._meCraftBusyUntil = computer.uptime() + self._meCraftCooldown
        return
      end

      self._meCraftQueue = nil
      self._meCraftBusyUntil = nil
      self.stateMachine:setState(self.stateMachine.states.idle)
    end

    cycleEndLib.register(self, function()
      if self.stateMachine.currentState == self.stateMachine.states.waitEnd then
        self._meCraftQueue = nil
        self._meCraftBusyUntil = nil
        self.stateMachine:setState(self.stateMachine.states.craftQuarks)
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
    self._meCraftQueue = nil
  end

  function obj:findMachineProxy()
    local machineName = self.config.machineName or "multimachine.purificationunitextractor"
    self.controllerProxy = componentDiscoverLib.discoverGtMachine(machineName, self.config.machineAddress)

    if self.controllerProxy == nil then
      error("[T8] Absolute Baryonic Perfection Purification Unit not found")
    end

    self.transposerProxy = componentDiscoverLib.discoverProxy(
      self.config.transposerAddress,
      "[T8] Transposer",
      "transposer")
    self.subMeInterfaceProxy = componentDiscoverLib.discoverProxy(
      self.config.subMeInterfaceAddress,
      "[T8] Sub Me Interface",
      "me_interface")
    self.gtSensorParser = gtSensorParserLib:new(self.controllerProxy)
  end

  function obj:findTransposerItem(proxy, itemLabels)
    local result, skipped = componentDiscoverLib.discoverTransposerItemStorage(proxy, itemLabels, {sides.up})

    if #skipped ~= 0 then
      error("[T8] Can't find items: "..table.concat(skipped, ", "))
    end

    for key, value in pairs(result) do
      self.transposerItems[key] = value
    end
  end

  function obj:putQuarks(index)
    local drops = {
      {
        "Up-Quark Releasing Catalyst",
        "Down-Quark Releasing Catalyst",
        "Strange-Quark Releasing Catalyst",
        "Charm-Quark Releasing Catalyst",
        "Bottom-Quark Releasing Catalyst",
        "Top-Quark Releasing Catalyst"
      },
      {
        "Up-Quark Releasing Catalyst",
        "Strange-Quark Releasing Catalyst",
        "Bottom-Quark Releasing Catalyst",
        "Down-Quark Releasing Catalyst",
        "Top-Quark Releasing Catalyst",
        "Charm-Quark Releasing Catalyst"
      },
      {
        "Up-Quark Releasing Catalyst",
        "Bottom-Quark Releasing Catalyst",
        "Down-Quark Releasing Catalyst",
        "Charm-Quark Releasing Catalyst",
        "Strange-Quark Releasing Catalyst",
        "Top-Quark Releasing Catalyst"
      }
    }

    self.stateMachine.data.lastPut = index

    for i = 1, 6, 1 do
      local transfered = self.transposerProxy.transferItem(
        self.transposerItems[drops[index][i]].side,
        sides.up,
        1,
        self.transposerItems[drops[index][i]].slot)

      if transfered == 0 then
        self.controllerProxy.setWorkAllowed(false)
        event.push("log_warning", "[T8] Not enough quarks on slot: "..drops[index][i])
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
        return false
      end
    end
    return true
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

return t8controller