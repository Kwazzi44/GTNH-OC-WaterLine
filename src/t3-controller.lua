local component = require("component")
local event = require("event")
local sides = require("sides")

local t3controller = {}

function t3controller:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  obj.transposer = nil
  
  obj.state = "idle"

  local function getConsumedCount()
    if not obj.proxy then return nil end
    local success, info = pcall(obj.proxy.getSensorInformation)
    if not success or not info then return nil end
    
    for _, line in ipairs(info) do
      if line:find("Polyaluminium Chloride consumed this cycle:") then
        local countStr = line:match("Polyaluminium Chloride consumed this cycle:%s*§?%w?(%d+)")
        if countStr then
          return tonumber(countStr)
        end
      end
    end
    return nil
  end

  local function transferFluidOrItem(transposer, fluidNamePart, itemNamePart, amount)
    if not transposer then return false, "no transposer" end
    
    -- 1. Сначала пытаемся как жидкость
    local sidesWithFluid = {}
    local emptyTanks = {}
    
    for side = 0, 5 do
      local success, tanks = pcall(transposer.getFluidInTank, side)
      if success and tanks then
        local fluid = tanks[1]
        if fluid and fluid.amount > 0 then
          obj.logger:debug(string.format("T3: Сторона %d имеет жидкость %s (%s) объемом %d мб", side, tostring(fluid.name), tostring(fluid.label), fluid.amount))
          if fluid.name and (fluid.name:lower():find(fluidNamePart:lower()) or (fluid.label and fluid.label:lower():find(fluidNamePart:lower()))) then
            table.insert(sidesWithFluid, { side = side, amount = fluid.amount })
          end
        else
          obj.logger:debug(string.format("T3: Сторона %d - пустой резервуар/люк", side))
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
    
    obj.logger:debug(string.format("T3: Найдено источника=%s, пустых приемников=%d. Итог: Источник=%s, Приемник=%s", tostring(#sidesWithFluid), #emptyTanks, tostring(sourceSide), tostring(sinkSide)))
    
    if sourceSide and sinkSide then
      obj.logger:debug(string.format("T3: Попытка transferFluid с %s на %s, кол-во: %d", tostring(sourceSide), tostring(sinkSide), amount))
      local ok, transferred = pcall(transposer.transferFluid, sourceSide, sinkSide, amount)
      obj.logger:debug(string.format("T3: Результат transferFluid: ok=%s, transferred=%s", tostring(ok), tostring(transferred)))
      if ok and transferred then
        local amt = (type(transferred) == "number" and transferred) or amount
        if (type(transferred) == "number" and transferred > 0) or (type(transferred) == "boolean" and transferred == true) then
          return true, "fluid", amt
        end
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
      if ok and transferred then
        local amt = (type(transferred) == "number" and transferred) or amount
        if (type(transferred) == "number" and transferred > 0) or (type(transferred) == "boolean" and transferred == true) then
          return true, "item", amt
        end
      end
    end
    
    return false, "not found"
  end

  function obj:init()
    self.logger:info("Инициализация T3 Controller...")
    
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

    if self.config.transposerAddress and self.config.transposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.transposerAddress)
      if success then self.transposer = proxy end
    end

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    
    local stateMod = require("lib.state")
    local theme = require("lib.theme")
    stateMod.t3.status = "IDLE"
    stateMod.t3.color = theme.C.text
    
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local consumed = getConsumedCount()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Потреблено: %s", self.state, tostring(hasWork), tostring(consumed)))

    local stateMod = require("lib.state")
    local theme = require("lib.theme")

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в work.")
        self.state = "work"
        stateMod.t3.status = "WORKING"
        stateMod.t3.color = theme.C.warn
      end
    elseif self.state == "work" then
      if consumed and consumed >= (self.config.requiredCount or 900000) then
        self.logger:info("Потреблено достаточное количество. Переход в waitEnd.")
        self.state = "waitEnd"
        stateMod.t3.status = "WAITING"
        stateMod.t3.color = theme.C.partial
        return
      end

      if self.transposer then
        local ok, type, transferred = transferFluidOrItem(self.transposer, "polyaluminium", "polyaluminium", 10000)
        if ok then
          self.logger:info(string.format("Добавлено Polyaluminium Chloride (%s): %s mB/шт", type, tostring(transferred)))
        else
          self.logger:warning("Не удалось добавить Polyaluminium Chloride (проверьте наличие в буфере)")
        end
      else
        self.logger:warning("Транспозер для T3 не подключен!")
      end
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Возврат в idle.")
        self.state = "idle"
        stateMod.t3.status = "IDLE"
        stateMod.t3.color = theme.C.text
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
          stateMod.t3.status = "IDLE"
          stateMod.t3.color = theme.C.text
        end
      end
    end
  end

  function obj:getState()
    return string.format("State: [%s]", self.state)
  end

  return obj
end

return t3controller
