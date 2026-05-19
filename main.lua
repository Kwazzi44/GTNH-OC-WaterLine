package.path = "/home/?.lua;/home/?/init.lua;" .. package.path

local thread = require("thread")
local event = require("event")
local keyboard = require("keyboard")

-- Добавим вывод в консоль для отладки "зависаний" при старте
print("Загрузка конфигурации...")
package.loaded.config = nil -- Очистим кеш на случай перезапуска
local config = require("config")

-- Попробуем загрузить реестр и объединить его с конфигурацией
local filesystem = pcall(require, "filesystem") and require("filesystem")
if filesystem then
  local registryPath = "/home/registry.lua"
  if filesystem.exists(registryPath) then
    local ok, reg = pcall(loadfile(registryPath))
    if ok and type(reg) == "table" then
      -- Объединяем lineController
      if reg.lineController then
        if reg.lineController.machineAddress then
          config.lineController.machineAddress = reg.lineController.machineAddress
        end
      end
      -- Объединяем controllers
      if reg.controllers then
        for tier, regData in pairs(reg.controllers) do
          if config.controllers[tier] then
            local c = config.controllers[tier]
            local hasAnyAddress = false
            for k, v in pairs(regData) do
              if v and v ~= "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" then
                c[k] = v
                hasAnyAddress = true
              end
            end
            if hasAnyAddress then
              c.enable = true
            end
          end
        end
      end
    end
  end
end


-- Инициализация логгера
print("Инициализация логгера...")
local loggerLib = require("lib.logger")
local mainLogger = loggerLib:new(config.logger, "[Main]")

mainLogger:info("Программа запускается...")

-- Загрузка контроллеров
mainLogger:info("Загрузка библиотек контроллеров...")
local lineControllerLib = require("src.line-controller")
local lineController = lineControllerLib:new(config.lineController, loggerLib:new(config.logger, "[Line]"))

local controllers = {}
local threads = {}

-- Инициализация Line Controller
mainLogger:info("Инициализация Line Controller...")
if lineController:init() then
  mainLogger:info("Запуск потока для Line Controller...")
  local t = thread.create(function()
    while true do
      lineController:loop()
      os.sleep(config.lineController.pollInterval or 1)
    end
  end)
  t:detach()
  table.insert(threads, t)
else
  mainLogger:error("Не удалось инициализировать Line Controller. Выход.")
  os.exit(1)
end

-- Инициализация и запуск контроллеров тиров
mainLogger:info("Поиск и инициализация контроллеров тиров...")
for key, controllerConfig in pairs(config.controllers) do
  if controllerConfig.enable then
    mainLogger:info("Включен контроллер " .. key .. ". Загрузка...")
    
    local success, lib = pcall(require, "src." .. key .. "-controller")
    if success then
      local ctrlLogger = loggerLib:new(config.logger, "[" .. key:upper() .. "]")
      local ctrl = lib:new(controllerConfig, ctrlLogger)
      
      if ctrl:init() then
        mainLogger:info("Запуск потока для " .. key .. "...")
        local t = thread.create(function()
          while true do
            ctrl:loop()
            os.sleep(controllerConfig.pollInterval or 0.5)
          end
        end)
        t:detach()
        table.insert(threads, t)
        controllers[key] = ctrl
      else
        mainLogger:warning("Не удалось инициализировать контроллер " .. key)
      end
    else
      mainLogger:warning("Не удалось загрузить файл src/" .. key .. "-controller.lua")
    end
  end
end

mainLogger:info("Все потоки запущены. Инициализация GUI...")

local gui = require("lib.gui")
local state = require("lib.state")
local logViewer = require("lib.log_viewer")

gui.init()
gui.drawLayout()
config.logger.printToScreen = false

-- Ожидание выхода и обновление экрана
while true do
  local ev, _, _, keyCode = event.pull(0.5, "key_up")
  
  if ev == "key_up" then
    if keyCode == keyboard.keys.q then
      -- Восстанавливаем цвета терминала перед выходом
      local comp = require("component")
      if comp.gpu then
        comp.gpu.setBackground(0x000000)
        comp.gpu.setForeground(0xFFFFFF)
        require("term").clear()
      end
      
      mainLogger:info("Получен сигнал выхода (Q). Останавливаем потоки...")
      for _, t in ipairs(threads) do
        pcall(t.kill, t)
      end
      break
    elseif keyCode == keyboard.keys.f1 then
      -- Запуск Setup
      local comp = require("component")
      if comp.gpu then
        comp.gpu.setBackground(0x000000)
        comp.gpu.setForeground(0xFFFFFF)
        require("term").clear()
      end
      
      print("Запуск мастера настройки...")
      os.sleep(1)
      os.execute("lua /home/setup.lua")
      
      -- После выхода из setup перерисовываем GUI
      gui.init()
      gui.drawLayout()
    elseif keyCode == keyboard.keys.f3 then
      gui.init()
      gui.drawLayout()
    elseif keyCode == keyboard.keys.f4 then
      -- Открываем встроенный GUI для просмотра логов
      logViewer.show(config)
      
      -- После выхода из просмотрщика перерисовываем GUI
      gui.init()
      gui.drawLayout()
    elseif keyCode == keyboard.keys.f5 then
      -- Запуск обновления
      local comp = require("component")
      if comp.gpu then
        comp.gpu.setBackground(0x000000)
        comp.gpu.setForeground(0xFFFFFF)
        require("term").clear()
      end
      
      print("Запуск обновления программы...")
      for _, t in ipairs(threads) do
        pcall(t.kill, t)
      end
      
      os.execute("lua /home/update.lua")
      break -- Выходим из программы
    end
  end
  
  -- Обновляем карточки из state
  for tier, data in pairs(state) do
    gui.updateCardStatus(tier, data.status, data.color)
  end
end

mainLogger:info("Программа успешно завершена.")
