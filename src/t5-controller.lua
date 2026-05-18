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

    if self.config.plasmaTransposerAddress and self.config.plasmaTransposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.plasmaTransposerAddress)
      if success then self.plasmaTransposer = proxy end
    end
    
    if self.config.coolantTransposerAddress and self.config.coolantTransposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.coolantTransposerAddress)
      if success then self.coolantTransposer = proxy end
    end

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local temp = getTemperature()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Темп: %s", self.state, tostring(hasWork), tostring(temp)))

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в heating.")
        self.iterations = 0
        self.state = "heating"
      end
    elseif self.state == "heating" then
      if self.iterations >= 2 then
        self.logger:info("Достигнут лимит итераций (2). Переход в waitEnd.")
        self.state = "waitEnd"
        return
      end

      -- Здесь должна быть логика заливки плазмы
      -- Для отладки просто пишем в лог
      self.logger:info("Нагрев: заливка плазмы (симуляция).")
      
      -- Ждем пока нагреется
      if temp and temp >= 10000 then
        self.logger:info("Температура достигла 10000. Переход в cooling.")
        self.state = "cooling"
      end
    elseif self.state == "cooling" then
      -- Здесь должна быть логика заливки хладагента
      self.logger:info("Охлаждение: заливка хладагента (симуляция).")

      -- Ждем пока остынет
      if temp and temp <= 0 then
        self.logger:info("Температура упала до 0. Возврат в heating, итерация +1.")
        self.iterations = self.iterations + 1
        self.state = "heating"
      end
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
      -- В параллельном потоке мы можем позволить себе ждать ивент с таймаутом!
      local ev, arg = event.pull(10, "cycle_end")
      if ev then
        self.logger:info("Получено событие cycle_end. Возврат в idle.")
        self.state = "idle"
      else
        self.logger:warning("Таймаут ожидания cycle_end. Проверяем работу машины.")
        if not hasWork then
          self.logger:info("Машина не работает. Возврат в idle.")
          self.state = "idle"
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
