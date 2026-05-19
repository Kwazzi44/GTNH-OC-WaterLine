local component = require("component")
local event = require("event")

local lineController = {}

function lineController:new(config, logger)
  local obj = {}
  obj.config = config
  obj.logger = logger
  obj.proxy = nil
  local lastWorkProgress = 0

  function obj:init()
    self.logger:info("Инициализация Line Controller...")
    
    if self.config.machineAddress and self.config.machineAddress ~= "" then
      local proxy = component.proxy(self.config.machineAddress)
      if proxy then
        self.proxy = proxy
        self.logger:info("Машина найдена по адресу из реестра: " .. self.config.machineAddress)
        return true
      else
        self.logger:warning("Машина с адресом " .. self.config.machineAddress .. " из реестра не найдена. Пытаемся найти по имени.")
      end
    end

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

    self.logger:info("Машина " .. self.config.machineName .. " найдена.")
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    local success2, workProgress = pcall(self.proxy.getWorkProgress)

    if not success or not success2 then
      self.logger:warning("Ошибка связи с машиной. Возможно, она отключена.")
      return
    end

    if lastWorkProgress > workProgress or (hasWork == false and lastWorkProgress ~= 0) then
      self.logger:info("Обнаружен конец цикла. Отправка события cycle_end.")
      event.push("cycle_end")
      lastWorkProgress = 0
    end

    if hasWork then
      lastWorkProgress = workProgress
    end
  end

  function obj:getState()
    if not self.proxy then return "nil" end
    
    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return "error" end

    if hasWork then
      local success2, progress = pcall(self.proxy.getWorkProgress)
      local success3, maxProgress = pcall(self.proxy.getWorkMaxProgress)
      if success2 and success3 then
        return string.format("%d/%d", math.ceil(progress/20), math.ceil(maxProgress/20))
      end
    end

    return "Disable"
  end

  return obj
end

return lineController
