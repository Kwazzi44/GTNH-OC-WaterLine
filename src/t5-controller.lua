local component = require("component")
local event = require("event")
local sides = require("sides")

local t5controller = {}

function t5controller:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  obj.plasmaTransposer = nil
  obj.coolantTransposer = nil
  
  obj.state = "idle"
  obj.iterations = 0

  local function getTemperature()
    if not obj.proxy then return nil end
    local success, info = pcall(obj.proxy.getSensorInformation)
    if not success or not info then return nil end
    
    for _, line in ipairs(info) do
      if line:find("Current temperature:") then
        -- Извлекаем число. В GT оно может быть с цветом, например "§c10000"
        local tempStr = line:match("Current temperature:%s*§?%w?(%d+)")
        if tempStr then
          return tonumber(tempStr)
        end
      end
    end
    return nil
  end

  function obj:init()
    self.logger:info("Инициализация T5 Controller...")
    
    -- Ищем компонент типа gt_machine и сверяем имя через getName()
    for address, name in component.list("gt_machine") do
      local proxy = component.proxy(address)
      if proxy and proxy.getName() == self.config.machineName then
        self.proxy = proxy
        break
      end
    end

    if not self.proxy then
      self.logger:error("Машина " .. self.config.machineName .. " не найдена!")
      return false
    end

  local function transferFluidOrItem(transposer, fluidNamePart, itemNamePart, amount)
    if not transposer then return false, "no transposer" end
    
    -- 1. Сначала пытаемся как жидкость
    local sidesWithFluid = {}
    local emptyTanks = {}
    
    for side = 0, 5 do
      local success, tanks = pcall(transposer.getFluidInTank, side)
      if success and tanks and #tanks > 0 then
        local fluid = tanks[1]
        if fluid and fluid.amount > 0 and fluid.name and (fluid.name:lower():find(fluidNamePart:lower()) or (fluid.label and fluid.label:lower():find(fluidNamePart:lower()))) then
          table.insert(sidesWithFluid, { side = side, amount = fluid.amount })
        else
          table.insert(emptyTanks, side)
        end
      end
    end
    
    local sourceSide, sinkSide = nil, nil
    if #sidesWithFluid == 1 then
      sourceSide = sidesWithFluid[1].side
      if #emptyTanks > 0 then
        sinkSide = emptyTanks[1]
      end
    elseif #sidesWithFluid >= 2 then
      table.sort(sidesWithFluid, function(a, b) return a.amount > b.amount end)
      sourceSide = sidesWithFluid[1].side
      sinkSide = sidesWithFluid[#sidesWithFluid].side
    end
    
    if sourceSide and sinkSide then
      local ok, transferred = pcall(transposer.transferFluid, sourceSide, sinkSide, amount)
      if ok and transferred and transferred > 0 then
        return true, "fluid", transferred
      end
    end
    
    -- 2. Если жидкость не сработала, пытаемся как предмет
    local sidesWithItem = {}
    local emptyInventories = {}
    
    for side = 0, 5 do
      local success, size = pcall(transposer.getInventorySize, side)
      if success and size and size > 0 then
        local foundCount = 0
        local foundSlot = nil
        for slot = 1, size do
          local succ2, stack = pcall(transposer.getStackInSlot, side, slot)
          if succ2 and stack and stack.size > 0 and stack.name and (stack.name:lower():find(itemNamePart:lower()) or (stack.label and stack.label:lower():find(itemNamePart:lower()))) then
            foundCount = foundCount + stack.size
            if not foundSlot then foundSlot = slot end
          end
        end
        
        if foundCount > 0 then
          table.insert(sidesWithItem, { side = side, slot = foundSlot, count = foundCount })
        else
          table.insert(emptyInventories, side)
        end
      end
    end
    
    local itemSourceSide, itemSinkSide = nil, nil
    local sourceSlot = nil
    
    if #sidesWithItem == 1 then
      itemSourceSide = sidesWithItem[1].side
      sourceSlot = sidesWithItem[1].slot
      if #emptyInventories > 0 then
        itemSinkSide = emptyInventories[1]
      end
    elseif #sidesWithItem >= 2 then
      table.sort(sidesWithItem, function(a, b) return a.count > b.count end)
      itemSourceSide = sidesWithItem[1].side
      sourceSlot = sidesWithItem[1].slot
      itemSinkSide = sidesWithItem[#sidesWithItem].side
    end
    
    if itemSourceSide and itemSinkSide and sourceSlot then
      local ok, transferred = pcall(transposer.transferItem, itemSourceSide, itemSinkSide, amount, sourceSlot)
      if ok and transferred and transferred > 0 then
        return true, "item", transferred
      end
    end
    
    return false, "not found"
  end

  function obj:init()
    self.logger:info("Инициализация T5 Controller...")
    
    -- Ищем компонент типа gt_machine и сверяем имя через getName()
    for address, name in component.list("gt_machine") do
      local proxy = component.proxy(address)
      if proxy and proxy.getName() == self.config.machineName then
        self.proxy = proxy
        break
      end
    end

    if not self.proxy then
      self.logger:error("Машина " .. self.config.machineName .. " не найдена!")
      return false
    end

    if self.config.plasmaTransposerAddress and self.config.plasmaTransposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.plasmaTransposerAddress)
      if success then self.plasmaTransposer = proxy end
    end
    
    if self.config.coolantTransposerAddress and self.config.coolantTransposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.coolantTransposerAddress)
      if success then self.coolantTransposer = proxy end
    end

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    
    local stateMod = require("lib.state")
    local theme = require("lib.theme")
    stateMod.t5.status = "IDLE"
    stateMod.t5.color = theme.C.text
    
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local temp = getTemperature()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Темп: %s", self.state, tostring(hasWork), tostring(temp)))

    local stateMod = require("lib.state")
    local theme = require("lib.theme")

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в heating.")
        self.iterations = 0
        self.state = "heating"
        stateMod.t5.status = "HEATING"
        stateMod.t5.color = theme.C.warn
      end
    elseif self.state == "heating" then
      if self.iterations >= 2 then
        self.logger:info("Достигнут лимит итераций (2). Переход в waitEnd.")
        self.state = "waitEnd"
        stateMod.t5.status = "WAITING"
        stateMod.t5.color = theme.C.partial
        return
      end

      -- Добавляем плазму для нагрева
      if self.plasmaTransposer then
        local amount = self.config.plasmaCount or 100
        local ok, type, transferred = transferFluidOrItem(self.plasmaTransposer, "plasma", "plasma", amount)
        if ok then
          self.logger:info("Нагрев: залито плазмы: " .. tostring(transferred) .. " mB")
        else
          self.logger:warning("Не удалось подать плазму (проверьте буфер/бак)")
        end
      else
        self.logger:warning("Транспозер плазмы не подключен!")
      end
      
      -- Ждем пока нагреется
      if temp and temp >= 10000 then
        self.logger:info("Температура достигла 10000. Переход в cooling.")
        self.state = "cooling"
        stateMod.t5.status = "COOLING"
        stateMod.t5.color = theme.C.partial
      end
    elseif self.state == "cooling" then
      -- Добавляем хладагент для охлаждения
      if self.coolantTransposer then
        local amount = self.config.coolantCount or 2000
        local ok, type, transferred = transferFluidOrItem(self.coolantTransposer, "coolant", "coolant", amount)
        if ok then
          self.logger:info("Охлаждение: залито хладагента: " .. tostring(transferred) .. " mB")
        else
          self.logger:warning("Не удалось подать хладагент (проверьте буфер/бак)")
        end
      else
        self.logger:warning("Транспозер хладагента не подключен!")
      end

      -- Ждем пока остынет
      if temp and temp <= 0 then
        self.logger:info("Температура упала до 0. Возврат в heating, итерация +1.")
        self.iterations = self.iterations + 1
        self.state = "heating"
        stateMod.t5.status = "HEATING"
        stateMod.t5.color = theme.C.warn
      end
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      -- В параллельном потоке мы можем позволить себе ждать ивент с таймаутом!
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Возврат в idle.")
        self.state = "idle"
        stateMod.t5.status = "IDLE"
        stateMod.t5.color = theme.C.text
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
          stateMod.t5.status = "IDLE"
          stateMod.t5.color = theme.C.text
        end
      end
    end
  end

  function obj:getState()
    return string.format("State: [%s] Iter: [%d]", self.state, self.iterations)
  end

  return obj
end

return t5controller
