local component = require("component")
local event = require("event")
local sides = require("sides")

local t8controller = {}

function t8controller:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  obj.transposer = nil
  obj.meInterface = nil
  
  obj.state = "idle"
  obj.lastPut = 0

  local function checkSensorYes()
    if not obj.proxy then return false end
    local success, info = pcall(obj.proxy.getSensorInformation)
    if not success or not info then return false end
    
    -- Проверяем последнюю строку на наличие "Yes"
    local lastLine = info[#info]
    if lastLine and lastLine:find("Yes") then
      return true
    end
    return false
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

  local function findT8Sides(transposer)
    local chestSide, machineSide = nil, nil
    for side = 0, 5 do
      local success, size = pcall(transposer.getInventorySize, side)
      if success and size and size > 0 then
        local slot = findItemInInventory(transposer, side, "quark")
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
    self.logger:info("Инициализация T8 Controller...")
    
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

    if self.config.subMeInterfaceAddress and self.config.subMeInterfaceAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.subMeInterfaceAddress)
      if success then self.meInterface = proxy end
    end

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    
    local stateMod = require("lib.state")
    local theme = require("lib.theme")
    stateMod.t8.status = "IDLE"
    stateMod.t8.color = theme.C.text
    
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local isYes = checkSensorYes()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Yes: %s", self.state, tostring(hasWork), tostring(isYes)))

    local stateMod = require("lib.state")
    local theme = require("lib.theme")

    if self.state == "idle" then
      if hasWork then
        if isYes then
          self.logger:info("Сенсор говорит 'Yes'. Пропуск шагов. Переход в waitEnd.")
          self.state = "waitEnd"
          stateMod.t8.status = "WAITING"
          stateMod.t8.color = theme.C.partial
        else
          self.logger:info("Сенсор говорит 'No'. Переход в putFirst.")
          self.state = "putFirst"
          stateMod.t8.status = "STEP 1"
          stateMod.t8.color = theme.C.warn
        end
      end
    elseif self.state == "putFirst" then
      self.logger:info("Шаг 1: Выкладываем кварки.")
      if self.transposer then
        local chest, mach = findT8Sides(self.transposer)
        if chest and mach then
          local slot, stack = findItemInInventory(self.transposer, chest, "quark")
          if slot then
            local toTransfer = math.min(self.config.maxQuarkCount or 4, stack.size)
            local ok, transferred = pcall(self.transposer.transferItem, chest, mach, toTransfer, slot)
            if ok and transferred and transferred > 0 then
              self.logger:info("Выложено кварков на шаге 1: " .. tostring(transferred))
            else
              self.logger:warning("Не удалось выложить кварки на шаге 1!")
            end
          else
            self.logger:warning("Кварки не найдены в сундуке!")
          end
        else
          self.logger:warning("Не удалось определить стороны сундука/машины!")
        end
      else
        self.logger:warning("Транспозер T8 не подключен!")
      end
      self.lastPut = 1
      self.state = "resultPutFirst"
      stateMod.t8.status = "CHECK 1"
      stateMod.t8.color = theme.C.warn
    elseif self.state == "resultPutFirst" then
      if isYes then
        self.logger:info("После шага 1 получили 'Yes'. Переход в waitEnd.")
        self.state = "waitEnd"
        stateMod.t8.status = "WAITING"
        stateMod.t8.color = theme.C.partial
      else
        self.logger:info("После шага 1 получили 'No'. Переход в putSecond.")
        self.state = "putSecond"
        stateMod.t8.status = "STEP 2"
        stateMod.t8.color = theme.C.warn
      end
    elseif self.state == "putSecond" then
      self.logger:info("Шаг 2: Выкладываем кварки.")
      if self.transposer then
        local chest, mach = findT8Sides(self.transposer)
        if chest and mach then
          local slot, stack = findItemInInventory(self.transposer, chest, "quark")
          if slot then
            local toTransfer = math.min(self.config.maxQuarkCount or 4, stack.size)
            local ok, transferred = pcall(self.transposer.transferItem, chest, mach, toTransfer, slot)
            if ok and transferred and transferred > 0 then
              self.logger:info("Выложено кварков на шаге 2: " .. tostring(transferred))
            else
              self.logger:warning("Не удалось выложить кварки на шаге 2!")
            end
          else
            self.logger:warning("Кварки не найдены в сундуке!")
          end
        else
          self.logger:warning("Не удалось определить стороны сундука/машины!")
        end
      else
        self.logger:warning("Транспозер T8 не подключен!")
      end
      self.lastPut = 2
      self.state = "resultPutSecond"
      stateMod.t8.status = "CHECK 2"
      stateMod.t8.color = theme.C.warn
    elseif self.state == "resultPutSecond" then
      if isYes then
        self.logger:info("После шага 2 получили 'Yes'. Переход в waitEnd.")
        self.state = "waitEnd"
        stateMod.t8.status = "WAITING"
        stateMod.t8.color = theme.C.partial
      else
        self.logger:info("После шага 2 получили 'No'. Переход в putThird.")
        self.state = "putThird"
        stateMod.t8.status = "STEP 3"
        stateMod.t8.color = theme.C.warn
      end
    elseif self.state == "putThird" then
      self.logger:info("Шаг 3: Выкладываем кварки.")
      if self.transposer then
        local chest, mach = findT8Sides(self.transposer)
        if chest and mach then
          local slot, stack = findItemInInventory(self.transposer, chest, "quark")
          if slot then
            local toTransfer = math.min(self.config.maxQuarkCount or 4, stack.size)
            local ok, transferred = pcall(self.transposer.transferItem, chest, mach, toTransfer, slot)
            if ok and transferred and transferred > 0 then
              self.logger:info("Выложено кварков на шаге 3: " .. tostring(transferred))
            else
              self.logger:warning("Не удалось выложить кварки на шаге 3!")
            end
          else
            self.logger:warning("Кварки не найдены в сундуке!")
          end
        else
          self.logger:warning("Не удалось определить стороны сундука/машины!")
        end
      else
        self.logger:warning("Транспозер T8 не подключен!")
      end
      self.lastPut = 3
      self.state = "waitEnd"
      stateMod.t8.status = "WAITING"
      stateMod.t8.color = theme.C.partial
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Переход в craftQuarks.")
        self.state = "craftQuarks"
        stateMod.t8.status = "CRAFTING"
        stateMod.t8.color = theme.C.warn
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
          stateMod.t8.status = "IDLE"
          stateMod.t8.color = theme.C.text
        end
      end
    elseif self.state == "craftQuarks" then
      self.logger:info("Заказ автокрафта кварков в МЭ...")
      if self.meInterface then
        local success, items = pcall(self.meInterface.getItemsInNetwork)
        if success and items then
          local targetItem = nil
          for _, item in ipairs(items) do
            if item.name and (item.name:lower():find("quark") or (item.label and item.label:lower():find("quark"))) then
              targetItem = item
              break
            end
          end
          if targetItem then
            local ok, err = pcall(self.meInterface.requestCrafting, targetItem, self.config.maxQuarkCount or 4)
            if ok then
              self.logger:info("Запрос на крафт кварков успешно отправлен.")
            else
              self.logger:warning("Не удалось отправить запрос на автокрафт: " .. tostring(err))
            end
          else
            self.logger:warning("Кварк не найден в МЭ-сети для заказа автокрафта.")
          end
        else
          self.logger:warning("Не удалось получить список предметов в МЭ-сети.")
        end
      else
        self.logger:warning("МЭ-интерфейс T8 не подключен!")
      end
      self.state = "idle"
      stateMod.t8.status = "IDLE"
      stateMod.t8.color = theme.C.text
    end
  end

  function obj:getState()
    return string.format("State: [%s]", self.state)
  end

  return obj
end

return t8controller
