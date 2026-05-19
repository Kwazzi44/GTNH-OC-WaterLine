-- main.lua
package.loaded.config = nil
local config = require("config")
local registry = require("registry")
local state = require("lib.state")
local input = require("lib.input-lib")

local PLACEHOLDER_ADDR = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

local componentDiscoverLib = require("lib.component-discover-lib")
componentDiscoverLib.invalidateMachineCache()

local configEnable = {}
for tier, tierCfg in pairs(config.controllers) do
  configEnable[tier] = tierCfg.enable == true
end

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
        if k == "enable" then
          c.enable = (v == true)
        elseif v and v ~= PLACEHOLDER_ADDR then
          c[k] = v
          hasAnyAddress = true
        end
      end
      if regConf.enable ~= nil then
        c.enable = (regConf.enable == true)
      elseif hasAnyAddress and configEnable[tier] ~= false then
        c.enable = true
      else
        c.enable = configEnable[tier] == true
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
local lineController = lineControllerLib:newFormConfig(config)
local activeControllers = {}
local controllerInitLib = require("lib.controller-init-lib")
local cycleEndLib = require("lib.cycle-end-lib")

local gui = require("lib.gui")
local logViewer = require("lib.log_viewer")

-- Show UI immediately so keyboard/GPU stay responsive during init
gui.init()
state.line.status = "INITIALIZING"
for _, tier in ipairs({"t3", "t4", "t5", "t6", "t7", "t8"}) do
  if state[tier] and config.controllers[tier] and config.controllers[tier].enable then
    state[tier].status = "INITIALIZING"
    state[tier].color = 0xB58900
  end
end
gui.drawLayout()

local tierInitKeys = {}
for _, tier in ipairs({"t3", "t4", "t5", "t6", "t7", "t8"}) do
  if config.controllers[tier] and config.controllers[tier].enable then
    table.insert(tierInitKeys, tier)
  end
end

local initPhase = "line"
local tierInitIndex = 1
local pendingTierCtrl = nil
local pendingTierKey = nil
local lineInitOk = false
local initComplete = false

local function shutdownControllers()
  for _, item in pairs(activeControllers) do
    if item.ctrl and item.ctrl.shutdown then
      pcall(function() item.ctrl:shutdown() end)
    end
  end
  cycleEndLib.clear()
end

local function finishInit()
  initComplete = true
  for key, controllerConfig in pairs(config.controllers) do
    if not controllerConfig.enable and state[key] then
      state[key].status = "DISABLED"
      state[key].color = 0x586E75
    end
  end
  mainLogger:info("All controllers initialized.")
end

local function runNextInitStep()
  if initPhase == "line" then
    local ok, err = pcall(function() lineController:init() end)
    if ok then
      mainLogger:info("WPP Line Controller initialized successfully.")
      lineInitOk = true
      state.line.status = "IDLE"
      state.line.color = 0x2AA198
    else
      mainLogger:error("Failed to initialize WPP Line Controller: " .. tostring(err))
      mainLogger:warning("Running in setup-only mode (tier cycle_end may use local fallback).")
      state.line.status = "NOT BOUND"
      state.line.color = 0xCB4B16
    end
    initPhase = "tier_load"
    return
  end

  if initPhase == "tier_load" then
    local key = tierInitKeys[tierInitIndex]
    if not key then
      finishInit()
      return
    end

    pendingTierKey = key
    local controllerConfig = config.controllers[key]
    state[key].status = "INITIALIZING"
    state[key].color = 0xB58900

    mainLogger:info("Initializing controller: " .. key:upper())
    local success, lib = pcall(require, "src." .. key .. "-controller")
    if not success then
      mainLogger:warning("Failed to load controller src/" .. key .. "-controller.lua: " .. tostring(lib))
      state[key].status = "INIT FAILED"
      state[key].color = 0xDC322F
      tierInitIndex = tierInitIndex + 1
      return
    end

    local ok, ctrl = pcall(function() return lib:newFormConfig(controllerConfig) end)
    if not ok or not ctrl then
      mainLogger:warning("Failed to instantiate controller " .. key:upper() .. ": " .. tostring(ctrl))
      state[key].status = "INIT FAILED"
      state[key].color = 0xDC322F
      tierInitIndex = tierInitIndex + 1
      return
    end

    pendingTierCtrl = ctrl
    controllerInitLib.begin(pendingTierCtrl)
    initPhase = "tier_step"
    return
  end

  if initPhase == "tier_step" then
    local done, err = controllerInitLib.step(pendingTierCtrl)
    if not done then
      return
    end

    local key = pendingTierKey
    local controllerConfig = config.controllers[key]

    if err then
      mainLogger:warning("Failed to init controller " .. key:upper() .. ": " .. tostring(err))
      state[key].status = "INIT FAILED"
      state[key].color = 0xDC322F
    else
      activeControllers[key] = {
        ctrl = pendingTierCtrl,
        pollInterval = controllerConfig.pollInterval or 0.5,
        lastPoll = 0
      }
      state[key].status = "IDLE"
      state[key].color = 0x2AA198
    end

    pendingTierCtrl = nil
    pendingTierKey = nil
    tierInitIndex = tierInitIndex + 1
    initPhase = "tier_load"
    if tierInitIndex > #tierInitKeys then
      finishInit()
    end
  end
end

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

local function handleKey(ev, addr, char, code)
  if not input.isKeyEvent(ev) then
    return false
  end

  if input.pressed(ev, code, char, keyboard.keys.q, string.byte("q")) then
    quitFlag = true
    return true
  elseif input.pressed(ev, code, char, keyboard.keys.f1) then
    shutdownControllers()
    event.ignore("log_info", onLogInfo)
    event.ignore("log_warning", onLogWarning)
    event.ignore("log_error", onLogError)
    if component.gpu then
      component.gpu.setActiveBuffer(0)
      pcall(component.gpu.freeAllBuffers)
      component.gpu.setBackground(0x000000)
      component.gpu.setForeground(0xFFFFFF)
      require("term").clear()
    end
    print("Starting setup utility...")
    os.execute("lua setup.lua")
    print("Rebooting computer...")
    computer.shutdown(true)
    quitFlag = true
    return true
  elseif input.pressed(ev, code, char, keyboard.keys.f3) then
    gui.init()
    gui.drawLayout()
  elseif input.pressed(ev, code, char, keyboard.keys.f4) then
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

  return false
end

while not quitFlag do
  -- Keyboard first: never starve input behind machine polling / redraw
  input.drain(handleKey)

  local now = computer.uptime()

  if not initComplete then
    runNextInitStep()
    gui.drawLayout()
    event.pull(0.02)
  else
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

    for key, item in pairs(activeControllers) do
      if now - item.lastPoll >= item.pollInterval then
        pcall(function() item.ctrl:loop() end)
        item.lastPoll = now
      end
    end

    if now - lastRedraw >= 1 then
      for key, item in pairs(activeControllers) do
        local stateName = "IDLE"
        local color = 0x839496
        local ctrl = item.ctrl

        local ok, res = pcall(function() return ctrl:getState() end)
        if ok and res then
          stateName = res:gsub("^State:%s*", "")
          local lowerState = stateName:lower()
          if lowerState:find("disabled") then
            color = 0x586E75
          elseif lowerState:find("wait") or lowerState:find("idle") then
            color = 0x2AA198
          else
            color = 0xCB4B16
          end
        else
          stateName = "ERROR"
          color = 0xDC322F
        end

        if state[key] then
          state[key].status = stateName
          state[key].color = color
        end
      end

      gui.drawLayout()
      lastRedraw = now
    end

    event.pull(0.05)
  end
end

shutdownControllers()

event.ignore("log_info", onLogInfo)
event.ignore("log_warning", onLogWarning)
event.ignore("log_error", onLogError)

if component.gpu then
  component.gpu.setActiveBuffer(0)
  pcall(component.gpu.freeAllBuffers)
  component.gpu.setBackground(0x000000)
  component.gpu.setForeground(0xFFFFFF)
  require("term").clear()
end
mainLogger:info("Water Line Control stopped.")
