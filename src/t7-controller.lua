local component = require("component")
local event = require("event")
local sides = require("sides")

local t7controller = {}

function t7controller:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  
  -- Транспозеры
  obj.inertGasTransposer = nil
  obj.superConductorTransposer = nil
  obj.neutroniumTransposer = nil
  obj.coolantTransposer = nil
  
  obj.state = "idle"

  local function getBitString()
    if not obj.proxy then return nil end
    local success, info = pcall(obj.proxy.getSensorInformation)
    if not success or not info then return nil end
    
    for _, line in ipairs(info) do
      if line:find("Current control signal (binary): 0b") then
        return line:match("Current control signal %(binary%): 0b(%w+)")
      end
    end
    return nil
  end

  local function bitParser(bitString)
    bitString = string.rep("0", 4 - #bitString)..bitString
    local bits = {
      tonumber(bitString:sub(4, 4)) == 1,
      tonumber(bitString:sub(3, 3)) == 1,
      tonumber(bitString:sub(2, 2)) == 1,
      tonumber(bitString:sub(1, 1)) == 1,
    }
    return bits
  end

  function obj:init()
    self.logger:info("Инициализация T7 Controller...")
    
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

    -- Инициализация прокси транспозеров
    local function getProxy(addr, name)
      if addr and addr ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
        local success, proxy = pcall(component.proxy, addr)
        if success then return proxy end
        self.logger:warning("Не удалось подключить транспозер " .. name)
      end
      return nil
    end

    self.inertGasTransposer = getProxy(self.config.inertGasTransposerAddress, "Inert Gas")
    self.superConductorTransposer = getProxy(self.config.superConductorTransposerAddress, "Super Conductor")
    self.neutroniumTransposer = getProxy(self.config.netroniumTransposerAddress, "Neutronium")
    self.coolantTransposer = getProxy(self.config.coolantTransposerAddress, "Coolant")

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    
    local stateMod = require("lib.state")
    local theme = require("lib.theme")
    stateMod.t7.status = "IDLE"
    stateMod.t7.color = theme.C.text
    
    return true
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
    self.logger:info("Инициализация T7 Controller...")
    
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

    -- Инициализация прокси транспозеров
    local function getProxy(addr, name)
      if addr and addr ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
        local success, proxy = pcall(component.proxy, addr)
        if success then return proxy end
        self.logger:warning("Не удалось подключить транспозер " .. name)
      end
      return nil
    end

    self.inertGasTransposer = getProxy(self.config.inertGasTransposerAddress, "Inert Gas")
    self.superConductorTransposer = getProxy(self.config.superConductorTransposerAddress, "Super Conductor")
    self.neutroniumTransposer = getProxy(self.config.netroniumTransposerAddress, "Neutronium")
    self.coolantTransposer = getProxy(self.config.coolantTransposerAddress, "Coolant")

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    
    local stateMod = require("lib.state")
    local theme = require("lib.theme")
    stateMod.t7.status = "IDLE"
    stateMod.t7.color = theme.C.text
    
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local bitString = getBitString()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Биты: %s", self.state, tostring(hasWork), tostring(bitString)))

    local stateMod = require("lib.state")
    local theme = require("lib.theme")

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в work.")
        self.state = "work"
        stateMod.t7.status = "WORKING"
        stateMod.t7.color = theme.C.warn
      end
    elseif self.state == "work" then
      if not bitString then
        self.logger:warning("Не удалось получить битовую строку. Ждем.")
        return
      end

      local bits = bitParser(bitString)
      self.logger:info(string.format("Парсинг бит: [%s, %s, %s, %s]", tostring(bits[1]), tostring(bits[2]), tostring(bits[3]), tostring(bits[4])))

      if bits[4] == true then
        self.logger:info("Бит 4 активен. Пропуск. Переход в waitEnd.")
        self.state = "waitEnd"
        stateMod.t7.status = "WAITING"
        stateMod.t7.color = theme.C.partial
        return
      end

      local transferSuccess = true

      if bits[1] == false and bits[2] == false and bits[3] == false then
        self.logger:info("Все биты 0. Требуется Coolant.")
        if self.coolantTransposer then
          local ok, type, transferred = transferFluidOrItem(self.coolantTransposer, "coolant", "coolant", 1000)
          if ok then
            self.logger:info("Залит Coolant: " .. tostring(transferred) .. " mB")
          else
            self.logger:warning("Не удалось залить Coolant")
            transferSuccess = false
          end
        else
          self.logger:warning("Транспозер Coolant не подключен!")
          transferSuccess = false
        end
      else
        if bits[1] == true then
          self.logger:info("Бит 1 активен. Требуется Inert Gas.")
          if self.inertGasTransposer then
            local ok, type, transferred = transferFluidOrItem(self.inertGasTransposer, "inert", "inert", 1000)
            if ok then
              self.logger:info("Залит Inert Gas: " .. tostring(transferred) .. " mB")
            else
              self.logger:warning("Не удалось залить Inert Gas")
              transferSuccess = false
            end
          else
            self.logger:warning("Транспозер Inert Gas не подключен!")
            transferSuccess = false
          end
        end
        if bits[2] == true then
          self.logger:info("Бит 2 активен. Требуется Super Conductor.")
          if self.superConductorTransposer then
            local ok, type, transferred = transferFluidOrItem(self.superConductorTransposer, "conductor", "conductor", 1000)
            if ok then
              self.logger:info("Залит Super Conductor: " .. tostring(transferred) .. " mB")
            else
              self.logger:warning("Не удалось залить Super Conductor")
              transferSuccess = false
            end
          else
            self.logger:warning("Транспозер Super Conductor не подключен!")
            transferSuccess = false
          end
        end
        if bits[3] == true then
          self.logger:info("Бит 3 активен. Требуется Neutronium.")
          if self.neutroniumTransposer then
            local ok, type, transferred = transferFluidOrItem(self.neutroniumTransposer, "neutronium", "neutronium", 1000)
            if ok then
              self.logger:info("Залит Neutronium: " .. tostring(transferred) .. " mB")
            else
              self.logger:warning("Не удалось залить Neutronium")
              transferSuccess = false
            end
          else
            self.logger:warning("Транспозер Neutronium не подключен!")
            transferSuccess = false
          end
        end
      end

      if transferSuccess then
        self.logger:info("Все требуемые ресурсы залиты. Переход в waitEnd.")
        self.state = "waitEnd"
        stateMod.t7.status = "WAITING"
        stateMod.t7.color = theme.C.partial
      end
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Возврат в idle.")
        self.state = "idle"
        stateMod.t7.status = "IDLE"
        stateMod.t7.color = theme.C.text
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
          stateMod.t7.status = "IDLE"
          stateMod.t7.color = theme.C.text
        end
      end
    end
  end

  function obj:getState()
    return string.format("State: [%s]", self.state)
  end

  return obj
end

return t7controller
