local component = require("component")
local event = require("event")
local sides = require("sides")

local t6controller = {}

function t6controller:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  obj.transposer = nil
  
  obj.state = "idle"
  obj.currentLens = nil

  local function getRequestedLens()
    if not obj.proxy then return nil end
    local success, info = pcall(obj.proxy.getSensorInformation)
    if not success or not info then return nil end
    
    for _, line in ipairs(info) do
      if line:find("Current lens requested:") then
        return line:match("Current lens requested:%s*(.*)")
      end
    end
    return nil
  end

  local function findItemInInventory(transposer, side, namePart)
    local success, size = pcall(transposer.getInventorySize, side)
    if not success or not size then return nil end
    local success2, stacks = pcall(transposer.getAllStacks, side)
    if not success2 or not stacks then return nil end
    local slot = 1
    for stack in stacks do
      if stack and stack.size > 0 then
        local name = stack.name or ""
        local label = stack.label or ""
        local cleanName = name:gsub("§.", ""):lower()
        local cleanLabel = label:gsub("§.", ""):lower()
        local cleanQuery = namePart:gsub("§.", ""):lower()
        if cleanName:find(cleanQuery) or cleanLabel:find(cleanQuery) then
          return slot, stack
        end
      end
      slot = slot + 1
    end
    return nil
  end

  local function findT6Sides(transposer, requestedLens)
    local chestSide, machineSide = nil, nil
    for side = 0, 5 do
      local success, size = pcall(transposer.getInventorySize, side)
      if success and size and size > 0 then
        local slot = findItemInInventory(transposer, side, requestedLens)
        if slot then
          chestSide = side
        else
          machineSide = side
        end
      end
    end
    if not chestSide or not machineSide then
      local sidesWithInv = {}
      for side = 0, 5 do
        local success, size = pcall(transposer.getInventorySize, side)
        if success and size and size > 0 then
          table.insert(sidesWithInv, side)
        end
      end
      if #sidesWithInv >= 2 then
        chestSide = sidesWithInv[1]
        machineSide = sidesWithInv[2]
      end
    end
    return chestSide, machineSide
  end

  function obj:init()
    self.logger:info("Инициализация T6 Controller...")
    
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
    stateMod.t6.status = "IDLE"
    stateMod.t6.color = theme.C.text
    
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local requestedLens = getRequestedLens()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Линза: %s", self.state, tostring(hasWork), tostring(requestedLens)))

    local stateMod = require("lib.state")
    local theme = require("lib.theme")

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в changeLens.")
        self.state = "changeLens"
        stateMod.t6.status = "LENS CHG"
        stateMod.t6.color = theme.C.warn
      end
    elseif self.state == "changeLens" then
      if not requestedLens then
        self.logger:warning("Не удалось определить требуемую линзу. Ждем.")
        return
      end

      self.logger:info("Требуется линза: " .. requestedLens)
      
      if self.transposer then
        local chest, mach = findT6Sides(self.transposer, requestedLens)
        if chest and mach then
          -- 1. Извлекаем старую линзу, если она есть
          local machSlot, machStack = findItemInInventory(self.transposer, mach, "Lens")
          if machSlot then
            self.logger:info("Извлечение старой линзы из машины: " .. machStack.label)
            pcall(self.transposer.transferItem, mach, chest, 1, machSlot)
          end

          -- 2. Вставляем новую линзу
          local chestSlot, chestStack = findItemInInventory(self.transposer, chest, requestedLens)
          if chestSlot then
            self.logger:info("Установка линзы: " .. chestStack.label)
            local ok, transferred = pcall(self.transposer.transferItem, chest, mach, 1, chestSlot)
            if ok and transferred and transferred > 0 then
              self.currentLens = requestedLens
            end
          else
            self.logger:warning("Линза " .. requestedLens .. " не найдена в сундуке!")
          end
        else
          self.logger:warning("Не удалось определить стороны сундука/машины для линзы!")
        end
      else
        self.logger:warning("Транспозер для T6 не подключен!")
      end

      if self.currentLens == requestedLens then
        -- Успешно заменили линзу
        -- Если это Dilithium Lens, то это финальный шаг рецепта (waitEnd)
        local cleanRequested = requestedLens:gsub("§.", ""):lower()
        if cleanRequested:find("dilithium") then
          self.logger:info("Установлена Dilithium Lens. Переход в waitEnd.")
          self.state = "waitEnd"
          stateMod.t6.status = "WAITING"
          stateMod.t6.color = theme.C.partial
        else
          self.logger:info("Переход в waitLens.")
          self.state = "waitLens"
          stateMod.t6.status = "WAIT LENS"
          stateMod.t6.color = theme.C.partial
        end
      end
    elseif self.state == "waitLens" then
      if not hasWork then
        self.logger:info("Работа завершена. Возврат в idle.")
        self.state = "idle"
        stateMod.t6.status = "IDLE"
        stateMod.t6.color = theme.C.text
        return
      end

      if requestedLens ~= self.currentLens then
        self.logger:info("Требуемая линза изменилась. Переход в changeLens.")
        self.state = "changeLens"
        stateMod.t6.status = "LENS CHG"
        stateMod.t6.color = theme.C.warn
      end
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Возврат в idle.")
        self.state = "idle"
        stateMod.t6.status = "IDLE"
        stateMod.t6.color = theme.C.text
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
          stateMod.t6.status = "IDLE"
          stateMod.t6.color = theme.C.text
        end
      end
    end
  end

  function obj:getState()
    return string.format("State: [%s] Lens: [%s]", self.state, tostring(self.currentLens))
  end

  return obj
end

return t6controller
