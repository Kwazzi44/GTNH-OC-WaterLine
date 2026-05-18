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
    return true
  end

  function obj:loop()
    if not self.proxy then return end

    local success, hasWork = pcall(self.proxy.hasWork)
    if not success then return end

    local bitString = getBitString()
    self.logger:debug(string.format("Статус: %s, Работа: %s, Биты: %s", self.state, tostring(hasWork), tostring(bitString)))

    if self.state == "idle" then
      if hasWork then
        self.logger:info("Обнаружена работа. Переход в work.")
        self.state = "work"
      end
    elseif self.state == "work" then
      if not bitString then
        self.logger:warning("Не удалось получить битовую строку. Ждем.")
        return
      end

      local bits = bitParser(bitString)
      self.logger:info(string.format("Парсинг бит: [%s, %s, %s, %s]", tostring(bits[1]), tostring(bits[2]), tostring(bits[3]), tostring(bits[4])))

      if bits[1] == false and bits[2] == false and bits[3] == false and bits[4] == false then
        self.logger:info("Все биты 0. Заливка Coolant (симуляция).")
        self.state = "waitEnd"
        return
      end

      if bits[4] == true then
        self.logger:info("Бит 4 активен. Пропуск. Переход в waitEnd.")
        self.state = "waitEnd"
        return
      end

      if bits[1] == true then
        self.logger:info("Бит 1 активен. Заливка Inert Gas (симуляция).")
      end
      if bits[2] == true then
        self.logger:info("Бит 2 активен. Заливка Super Conductor (симуляция).")
      end
      if bits[3] == true then
        self.logger:info("Бит 3 активен. Заливка Neutronium (симуляция).")
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

return t7controller
