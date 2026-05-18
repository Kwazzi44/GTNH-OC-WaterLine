local thread = require("thread")
local event = require("event")
local keyboard = require("keyboard")

-- Добавим вывод в консоль для отладки "зависаний" при старте
print("Загрузка конфигурации...")
package.loaded.config = nil -- Очистим кеш на случай перезапуска
local config = require("config")

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

mainLogger:info("Все потоки запущены. Нажмите 'Q' для выхода.")

-- Ожидание выхода
while true do
  local ev, _, _, keyCode = event.pull("key_up")
  if keyCode == keyboard.keys.q then
    mainLogger:info("Получен сигнал выхода (Q). Останавливаем потоки...")
    for _, t in ipairs(threads) do
      pcall(t.kill, t)
    end
    break
  end
end

mainLogger:info("Программа успешно завершена.")
