local theme = require("lib.theme")
local state = require("lib.state")
local component = require("component")
local logger = require("lib.logger")

local gui = {}
local gpu = nil
local W, H = 80, 25

function gui.init()
  gpu = component.gpu
  theme.init(gpu)
  W, H = theme.getRes()
  
  -- Clear screen with bg color
  theme.gfill(1, 1, W, H, " ", theme.C.text, theme.C.bg)
end

local function makeProgressBar(pct, width)
  local filled = math.floor((pct / 100) * width)
  filled = math.max(0, math.min(width, filled))
  return string.rep("=", filled) .. string.rep(".", width - filled)
end

function gui.drawLayout()
  -- ВКЛЮЧАЕМ БУФЕРИЗАЦИЮ ЭКРАНА (Убирает лаги и зависания)
  local hasBuffer = false
  local buf = nil
  if gpu.allocateBuffer then
    buf = gpu.allocateBuffer(W, H)
    if buf then
      gpu.setActiveBuffer(buf)
      hasBuffer = true
    end
  end

  -- Очистка фона в буфере
  theme.gfill(1, 1, W, H, " ", theme.C.text, theme.C.bg)

  -- WPP Subtitle calculation
  local subtitle = "LINE: DISABLED"
  if state.line and state.line.status and state.line.status ~= "DISABLED" then
    if state.line.status == "WORKING" and state.line.maxProgress and state.line.maxProgress > 0 then
      local pct = math.floor(state.line.progress / state.line.maxProgress * 100)
      local elapsed = math.ceil(state.line.progress / 20)
      local total = math.ceil(state.line.maxProgress / 20)
      local pbar = makeProgressBar(pct, 20)
      subtitle = string.format("LINE: ACTIVE [%s] %d%% (%ds/%ds)", pbar, pct, elapsed, total)
    else
      subtitle = "LINE: " .. state.line.status
    end
  end

  theme.drawHeader("WATER LINE CONTROL", subtitle)
  
  theme.drawFooter({
    {"F1", "Setup"},
    {"F3", "Redraw"},
    {"F4", "Logs"},
    {"Q", "Quit"},
  })
  
  gui.drawTierCards()
  gui.drawLogsBox()

  -- ВЫВОДИМ БУФЕР НА ЭКРАН ОДНИМ КАДРОМ
  if hasBuffer then
    gpu.bitblt(0, 1, 1, W, H, buf, 1, 1)
    gpu.freeAllBuffers()
  end
end

function gui.drawTierCards()
  local tiers = {"t3", "t4", "t5", "t6", "t7", "t8"}
  local cardW = 24
  local cardH = 5
  
  local startX = 3
  local startY = 5
  
  for i, tier in ipairs(tiers) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    
    local x = startX + col * (cardW + 2)
    local y = startY + row * (cardH + 2)
    
    local tierState = state[tier] or { status = "DISABLED", color = theme.C.dim }
    gui.drawCard(x, y, cardW, cardH, tier:upper(), tierState.status, tierState.color)
  end
end

function gui.drawCard(x, y, w, h, title, status, color)
  -- Border
  theme.gset(x, y, "+" .. string.rep("-", w - 2) .. "+", theme.C.border, theme.C.bg)
  for i = 1, h - 2 do
    theme.gset(x, y + i, "|", theme.C.border, theme.C.bg)
    theme.gset(x + w - 1, y + i, "|", theme.C.border, theme.C.bg)
    theme.gfill(x + 1, y + i, w - 2, 1, " ", theme.C.text, theme.C.bg)
  end
  theme.gset(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", theme.C.border, theme.C.bg)
  
  -- Title
  theme.gset(x + 2, y, "[ " .. title .. " ]", theme.C.title, theme.C.bg)
  
  -- Status
  local line1 = status
  local line2 = ""
  local successIdx = status:find("Success:")
  if successIdx then
    line1 = status:sub(1, successIdx - 1):gsub("%s+$", "")
    line2 = status:sub(successIdx)
  end

  theme.gset(x + 2, y + 2, "Status: ", theme.C.text, theme.C.bg)
  theme.gset(x + 10, y + 2, theme.pad(line1, w - 12), color, theme.C.bg)

  if line2 ~= "" then
    theme.gset(x + 2, y + 3, theme.pad(line2, w - 4), color, theme.C.bg)
  end
end

function gui.drawLogsBox()
  local logsY = 17
  local logsH = 5
  
  -- Draw border
  theme.gset(1, logsY, "+" .. string.rep("-", W - 2) .. "+", theme.C.border, theme.C.bg)
  theme.gset(3, logsY, "[ Live Logs ]", theme.C.title, theme.C.bg)
  
  for i = 1, logsH - 1 do
    local ry = logsY + i
    theme.gset(1, ry, "|", theme.C.border, theme.C.bg)
    theme.gset(W, ry, "|", theme.C.border, theme.C.bg)
    theme.gfill(2, ry, W - 2, 1, " ", theme.C.text, theme.C.bg)
  end
  
  -- Render logs
  local logList = logger.getMemoryLogs()
  local showCount = logsH - 1 -- 4 lines
  local startIdx = math.max(1, #logList - showCount + 1)
  
  for i = 0, showCount - 1 do
    local logIdx = startIdx + i
    local ry = logsY + 1 + i
    if logList[logIdx] then
      local log = logList[logIdx]
      -- Color code based on log level
      local col = theme.C.text
      if log.level == "WARNING" then col = theme.C.warn
      elseif log.level == "ERROR" then col = theme.C.ring_down
      elseif log.level == "DEBUG" then col = theme.C.dim
      end
      
      local lineStr = string.format("[%s] [%s] %s", log.time, log.tag, log.message)
      theme.gset(3, ry, theme.pad(lineStr, W - 5), col, theme.C.bg)
    end
  end
end

return gui
