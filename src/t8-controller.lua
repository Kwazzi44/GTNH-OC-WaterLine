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

  function obj:init()
    self.logger:info("Инициализация T8 Controller...")
    
    for address, name in component.list(self.config.machineName) do
      self.proxy = component.proxy(address)
      break
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
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local isYes = checkSensorYes()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Yes: %s", self.state, tostring(hasWork), tostring(isYes)))

    if self.state == "idle" then
      if hasWork then
        if isYes then
          self.logger:info("Сенсор говорит 'Yes'. Пропуск шагов. Переход в waitEnd.")
          self.state = "waitEnd"
        else
          self.logger:info("Сенсор говорит 'No'. Переход в putFirst.")
          self.state = "putFirst"
        end
      end
    elseif self.state == "putFirst" then
      self.logger:info("Шаг 1: Выкладываем кварки (симуляция).")
      self.lastPut = 1
      self.state = "resultPutFirst"
    elseif self.state == "resultPutFirst" then
      if isYes then
        self.logger:info("После шага 1 получили 'Yes'. Переход в waitEnd.")
        self.state = "waitEnd"
      else
        self.logger:info("После шага 1 получили 'No'. Переход в putSecond.")
        self.state = "putSecond"
      end
    elseif self.state == "putSecond" then
      self.logger:info("Шаг 2: Выкладываем кварки (симуляция).")
      self.lastPut = 2
      self.state = "resultPutSecond"
    elseif self.state == "resultPutSecond" then
      if isYes then
        self.logger:info("После шага 2 получили 'Yes'. Переход в waitEnd.")
        self.state = "waitEnd"
      else
        self.logger:info("После шага 2 получили 'No'. Переход в putThird.")
        self.state = "putThird"
      end
    elseif self.state == "putThird" then
      self.logger:info("Шаг 3: Выкладываем кварки (симуляция).")
      self.lastPut = 3
      self.state = "waitEnd"
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Переход в craftQuarks.")
        self.state = "craftQuarks"
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
        end
      end
    elseif self.state == "craftQuarks" then
      self.logger:info("Заказ крафта кварков в МЭ (симуляция).")
      -- Тут логика заказа крафта через meInterface
      os.sleep(3) -- Симуляция времени крафта
      self.logger:info("Крафт заказан. Возврат в idle.")
      self.state = "idle"
    end
  end

  function obj:getState()
    return string.format("State: [%s]", self.state)
  end

  return obj
end

return t8controller
