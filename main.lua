-- main.lua
package.loaded.config = nil
local config = require("config")
local registry = require("registry")

-- Load registry bindings and merge into config
local regData = registry.load()
if regData.lineController then
  if regData.lineController.machineAddress then
    config.lineController.machineAddress = regData.lineController.machineAddress
  end
end
if regData.controllers then
  for tier, regConf in pairs(regData.controllers) do
    if config.controllers[tier] then
      local c = config.controllers[tier]
      local hasAnyAddress = false
      for k, v in pairs(regConf) do
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

local event = require("event")
local keyboard = require("keyboard")
local computer = require("computer")
local component = require("component")

local loggerLib = require("lib.logger")
local mainLogger = loggerLib:new(config.logger, "Main")

mainLogger:info("Starting Water Line Control (Original Controllers Mode)...")

local lineControllerLib = require("src.line-controller")
local lineController = lineControllerLib:newFormConfig()

local activeControllers = {}

-- Initialize WPP Line Controller
local lineInitOk = false
if pcall(function() lineController:init() end) then
  mainLogger:info("WPP Line Controller initialized successfully.")
  lineInitOk = true
else
  mainLogger:error("Failed to initialize WPP Line Controller. Running in setup-only mode.")
  state.line.status = "NOT BOUND"
  state.line.color = 0xCB4B16 -- Warn color
end

-- Initialize T3-T8 controllers
for key, controllerConfig in pairs(config.controllers) do
  if controllerConfig.enable then
    mainLogger:info("Initializing controller: " .. key:upper())
    local success, lib = pcall(require, "src." .. key .. "-controller")
    if success then
      local ok, ctrl = pcall(function() return lib:newFormConfig(controllerConfig) end)
      if ok and ctrl then
        local initOk, err = pcall(function() ctrl:init() end)
        if initOk then
          activeControllers[key] = {
            ctrl = ctrl,
            pollInterval = controllerConfig.pollInterval or 0.5,
            lastPoll = 0
          }
        else
          mainLogger:warning("Failed to init controller " .. key:upper() .. ": " .. tostring(err))
        end
      else
        mainLogger:warning("Failed to instantiate controller " .. key:upper() .. ": " .. tostring(ctrl))
      end
    else
      mainLogger:warning("Failed to load controller src/" .. key .. "-controller.lua: " .. tostring(lib))
    end
  else
    local state = require("lib.state")
    if state[key] then
      state[key].status = "DISABLED"
      state[key].color = 0x586E75
    end
  end
end

local gui = require("lib.gui")
local state = require("lib.state")
local logViewer = require("lib.log_viewer")

gui.init()
gui.drawLayout()

-- Setup event listeners for log events pushed by original controllers
local function onLogInfo(_, msg) mainLogger:info(msg) end
local function onLogWarning(_, msg) mainLogger:warning(msg) end
local function onLogError(_, msg) mainLogger:error(msg) end

event.listen("log_info", onLogInfo)
event.listen("log_warning", onLogWarning)
event.listen("log_error", onLogError)

local lineInterval = config.lineController.pollInterval or 1
local lastLinePoll = 0
local lastRedraw = 0
local quitFlag = false

while not quitFlag do
  local now = computer.uptime()

  -- 1. Poll WPP Line Controller
  if now - lastLinePoll >= lineInterval then
    if lineInitOk and lineController.controllerProxy then
      pcall(function()
        lineController:loop()
        
        local proxy = lineController.controllerProxy
        local allowed = true
        pcall(function() allowed = proxy.isWorkAllowed() end)
        
        if not allowed then
          state.line.status = "DISABLED"
          state.line.progress = 0
          state.line.maxProgress = 0
        elseif proxy.hasWork() then
          state.line.status = "WORKING"
          state.line.progress = proxy.getWorkProgress()
          state.line.maxProgress = proxy.getWorkMaxProgress()
        else
          state.line.status = "IDLE"
          state.line.progress = 0
          state.line.maxProgress = 0
        end
      end)
    else
      state.line.status = "NOT BOUND"
      state.line.progress = 0
      state.line.maxProgress = 0
    end
    lastLinePoll = now
  end

  -- 2. Poll T3-T8 Controllers
  for key, item in pairs(activeControllers) do
    if now - item.lastPoll >= item.pollInterval then
      pcall(function() item.ctrl:loop() end)
      item.lastPoll = now
    end
  end

  -- 3. Redraw dashboard periodically and update telemetry statuses
  if now - lastRedraw >= 1 then
    for key, item in pairs(activeControllers) do
      local stateName = "IDLE"
      local color = 0x839496 -- Theme C.text
      local ctrl = item.ctrl
      
      local ok, res = pcall(function() return ctrl:getState() end)
      if ok and res then
        stateName = res
        -- Strip "State: " prefix
        stateName = stateName:gsub("^State:%s*", "")
        
        -- Determine color based on content
        local lowerState = stateName:lower()
        if lowerState:find("disabled") then
          color = 0x586E75 -- Disabled/dim color
        elseif lowerState:find("wait") or lowerState:find("idle") then
          color = 0x2AA198 -- Waiting/cyan color
        else
          color = 0xCB4B16 -- Working/warn/orange color
        end
      else
        stateName = "ERROR"
        color = 0xDC322F -- Red/error
      end
      
      if state[key] then
        state[key].status = stateName
        state[key].color = color
      end
    end
    
    gui.drawLayout()
    lastRedraw = now
  end

  -- 4. Yield / Poll for keyboard events (non-blocking)
  local ev, _, _, keyCode = event.pull(0.1, "key_down")
  if ev == "key_down" then
    if keyCode == keyboard.keys.q then
      quitFlag = true
    elseif keyCode == keyboard.keys.f1 then
      -- Unregister listener and run setup
      event.ignore("log_info", onLogInfo)
      event.ignore("log_warning", onLogWarning)
      event.ignore("log_error", onLogError)
      if component.gpu then
        component.gpu.setBackground(0x000000)
        component.gpu.setForeground(0xFFFFFF)
        require("term").clear()
      end
      print("Starting setup utility...")
      os.execute("lua setup.lua")
      
      -- Clean reboot
      print("Rebooting computer...")
      computer.shutdown(true)
      break
    elseif keyCode == keyboard.keys.f3 then
      gui.init()
      gui.drawLayout()
    elseif keyCode == keyboard.keys.f4 then
      event.ignore("log_info", onLogInfo)
      event.ignore("log_warning", onLogWarning)
      event.ignore("log_error", onLogError)
      logViewer.show(config)
      event.listen("log_info", onLogInfo)
      event.listen("log_warning", onLogWarning)
      event.listen("log_error", onLogError)
      gui.init()
      gui.drawLayout()
    end
  end
end

-- Cleanup before exit
event.ignore("log_info", onLogInfo)
event.ignore("log_warning", onLogWarning)
event.ignore("log_error", onLogError)

if component.gpu then
  component.gpu.setBackground(0x000000)
  component.gpu.setForeground(0xFFFFFF)
  require("term").clear()
end
mainLogger:info("Water Line Control stopped.")