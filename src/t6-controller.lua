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
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local requestedLens = getRequestedLens()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Линза: %s", self.state, tostring(hasWork), tostring(requestedLens)))

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в changeLens.")
        self.state = "changeLens"
      end
    elseif self.state == "changeLens" then
      if not requestedLens then
        self.logger:warning("Не удалось определить требуемую линзу. Ждем.")
        return
      end

      self.logger:info("Требуется линза: " .. requestedLens)
      
      -- Здесь должна быть логика переноса линзы
      self.logger:info("Установка линзы (симуляция).")
      self.currentLens = requestedLens

      if requestedLens == "Dilithium Lens" then
        self.logger:info("Установлена Dilithium Lens. Переход в waitEnd.")
        self.state = "waitEnd"
      else
        self.logger:info("Переход в waitLens.")
        self.state = "waitLens"
      end
    elseif self.state == "waitLens" then
      if not hasWork then
        self.logger:info("Работа завершена. Возврат в idle.")
        self.state = "idle"
        return
      end

      if requestedLens ~= self.currentLens then
        self.logger:info("Требуемая линза изменилась. Переход в changeLens.")
        self.state = "changeLens"
      end
    elseif self.state == "waitEnd" then
      self.logger:info("Ожидание события cycle_end...")
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
    return string.format("State: [%s] Lens: [%s]", self.state, tostring(self.currentLens))
  end

  return obj
end

return t6controller
