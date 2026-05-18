local theme = require("lib.theme")
local component = require("component")

local gui = {}
local gpu = nil
local W, H = 80, 25

function gui.init()
  gpu = component.gpu
  theme.init(gpu)
  W, H = theme.getRes()
  
  -- Очищаем экран цветом фона из темы
  theme.gfill(1, 1, W, H, " ", theme.C.text, theme.C.bg)
end

function gui.drawLayout()
  -- Рисуем шапку и подвал
  theme.drawHeader("WATER LINE CONTROL", "PARALLEL SYSTEM")
  theme.drawFooter({
    {"F1", "Setup"},
    {"F3", "Redraw"},
    {"F4", "Logs"},
    {"F5", "Update"},
    {"Q", "Quit"},
  })
  
  -- Рисуем сетку карточек для 6 тиров (T3 - T8)
  gui.drawTierCards()
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
    
    gui.drawCard(x, y, cardW, cardH, tier:upper(), "DISABLED", theme.C.dim)
  end
end

function gui.drawCard(x, y, w, h, title, status, color)
  -- Рамка карточки
  theme.gset(x, y, "+" .. string.rep("-", w - 2) .. "+", theme.C.border, theme.C.bg)
  for i = 1, h - 2 do
    theme.gset(x, y + i, "|", theme.C.border, theme.C.bg)
    theme.gset(x + w - 1, y + i, "|", theme.C.border, theme.C.bg)
    theme.gfill(x + 1, y + i, w - 2, 1, " ", theme.C.text, theme.C.bg)
  end
  theme.gset(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", theme.C.border, theme.C.bg)
  
  -- Заголовок карточки
  theme.gset(x + 2, y, "[ " .. title .. " ]", theme.C.title, theme.C.bg)
  
  -- Статус
  theme.gset(x + 2, y + 2, "Status: ", theme.C.text, theme.C.bg)
  theme.gset(x + 10, y + 2, status, color, theme.C.bg)
end

-- Функция для обновления только статуса в карточке
function gui.updateCardStatus(tier, status, color)
  local tiers = {"t3", "t4", "t5", "t6", "t7", "t8"}
  local cardW = 24
  local cardH = 5
  local startX = 3
  local startY = 5
  
  for i, t in ipairs(tiers) do
    if t == tier then
      local col = (i - 1) % 3
      local row = math.floor((i - 1) / 3)
      local x = startX + col * (cardW + 2)
      local y = startY + row * (cardH + 2)
      
      -- Очищаем старый статус и пишем новый
      theme.gfill(x + 10, y + 2, cardW - 11, 1, " ", theme.C.text, theme.C.bg)
      theme.gset(x + 10, y + 2, status, color, theme.C.bg)
      break
    end
  end
end

return gui
