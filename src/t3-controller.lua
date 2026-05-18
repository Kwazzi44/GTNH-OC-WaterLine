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

  function obj:init()
    self.logger:info("Инициализация T3 Controller...")
    
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

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local consumed = getConsumedCount()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Потреблено: %s", self.state, tostring(hasWork), tostring(consumed)))

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в work.")
        self.state = "work"
      end
    elseif self.state == "work" then
      if consumed and consumed >= (self.config.requiredCount or 900000) then
        self.logger:info("Потреблено достаточное количество. Переход в waitEnd.")
        self.state = "waitEnd"
        return
      end

      -- Здесь должна быть логика заливки жидкости
      self.logger:info("Добавление Polyaluminium Chloride (симуляция).")
      
      self.logger:info("Переход в waitEnd.")
      self.state = "waitEnd"
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
    return string.format("State: [%s]", self.state)
  end

  return obj
end

return t3controller
