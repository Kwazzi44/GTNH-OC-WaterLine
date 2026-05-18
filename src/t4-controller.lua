local component = require("component")
local event = require("event")
local sides = require("sides")

local t4controller = {}

function t4controller:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  obj.hydrochloricAcidTransposer = nil
  obj.sodiumHydroxideTransposer = nil
  
  obj.state = "idle"

  local function getPhValue()
    if not obj.proxy then return nil end
    local success, info = pcall(obj.proxy.getSensorInformation)
    if not success or not info then return nil end
    
    for _, line in ipairs(info) do
      if line:find("Current pH Value:") then
        local phStr = line:match("Current pH Value:%s*§?%w?([%d%.]+)")
        if phStr then
          return tonumber(phStr)
        end
      end
    end
    return nil
  end

  function obj:init()
    self.logger:info("Инициализация T4 Controller...")
    
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

    if self.config.hydrochloricAcidTransposerAddress and self.config.hydrochloricAcidTransposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.hydrochloricAcidTransposerAddress)
      if success then self.hydrochloricAcidTransposer = proxy end
    end

    if self.config.sodiumHydroxideTransposerAddress and self.config.sodiumHydroxideTransposerAddress ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
      local success, proxy = pcall(component.proxy, self.config.sodiumHydroxideTransposerAddress)
      if success then self.sodiumHydroxideTransposer = proxy end
    end

    self.logger:info("Инициализация завершена. Начальное состояние: idle.")
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local ph = getPhValue()
    self.logger:debug(string.format("Статус: %s, Работа: %s, pH: %s", self.state, tostring(hasWork), tostring(ph)))

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в work.")
        self.state = "work"
      end
    elseif self.state == "work" then
      if not ph then
        self.logger:warning("Не удалось определить pH. Ждем.")
        return
      end

      local diffPh = 7 - ph
      local count = math.floor(math.abs(diffPh / 0.01))

      if count == 0 then
        self.logger:info("pH в норме (7). Переход в waitEnd.")
        self.state = "waitEnd"
        return
      end

      if diffPh > 0 then
        self.logger:info("pH низкий (" .. ph .. "). Требуется Sodium Hydroxide: " .. count)
        -- Исправленный баг с кратностью 64
        local remaining = count
        while remaining > 0 do
          local toTransfer = math.min(remaining, 64)
          self.logger:info("Добавление Sodium Hydroxide: " .. toTransfer .. " шт (симуляция).")
          remaining = remaining - toTransfer
        end
      else
        self.logger:info("pH высокий (" .. ph .. "). Требуется Hydrochloric Acid: " .. count)
        self.logger:info("Добавление Hydrochloric Acid (симуляция).")
      end

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

return t4controller
