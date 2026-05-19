local theme = {}

local gpu = nil
local W, H = 80, 25

theme.C = {
  bg        = 0x002B36,
  header_bg = 0x073642,
  sel_bg    = 0x073642,
  sel_fg    = 0x268BD2,
  text      = 0x839496,
  dim       = 0x586E75,
  border    = 0x1D6680,
  title     = 0x268BD2,
  key       = 0xB58900,
  key_bg    = 0x002B36,

  ok        = 0x859900,
  warn      = 0xB58900,
  ring_down = 0xDC322F,
  unknown   = 0x586E75,
  partial   = 0x2AA198
}

function theme.init(custom_gpu)
  gpu = custom_gpu
  if gpu then
    W, H = gpu.getResolution()
  end
end

function theme.getRes()
  return W, H
end

function theme.beginDoubleBuffer()
  if not gpu or not gpu.allocateBuffer then
    return nil
  end
  local buf = gpu.allocateBuffer(W, H)
  if buf then
    gpu.setActiveBuffer(buf)
  end
  return buf
end

function theme.endDoubleBuffer(buf)
  if not gpu or not buf then
    return
  end
  gpu.bitblt(0, 1, 1, W, H, buf, 1, 1, W, H)
  gpu.setActiveBuffer(0)
  if gpu.freeBuffer then
    pcall(gpu.freeBuffer, buf)
  end
end

function theme.gset(x, y, text, fg, bg)
  if not gpu then return end
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.set(x, y, text)
end

function theme.gfill(x, y, w, h, ch, fg, bg)
  if not gpu then return end
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.fill(x, y, w, h, ch)
end

function theme.pad(s, n)
  s = tostring(s)
  local unicode = require("unicode")
  local len = unicode.len(s)
  if len > n then return unicode.sub(s, 1, n-1) .. "~" end
  return s .. string.rep(" ", n - len)
end

function theme.drawHeader(title, subtitle)
  if not gpu then return end
  local C = theme.C

  theme.gset(1, 1, "+" .. string.rep("-", W - 2) .. "+", C.border, C.bg)

  theme.gset(1, 2, "|", C.border, C.bg)
  local inner = W - 2
  local tag = "==[ " .. title .. " ]"
  local fill = string.rep("=", math.max(0, inner - #tag))
  theme.gset(2, 2, tag .. fill, C.title, C.bg)
  theme.gset(W, 2, "|", C.border, C.bg)

  theme.gset(1, 3, "|", C.border, C.bg)
  theme.gfill(2, 3, W - 2, 1, " ", C.dim, C.bg)
  if subtitle then
    theme.gset(3, 3, "STATUS: " .. subtitle, C.dim, C.bg)
  end
  theme.gset(W, 3, "|", C.border, C.bg)
end

function theme.drawFooter(keys)
  if not gpu then return end
  local C = theme.C
  theme.gset(1, H-2, "+" .. string.rep("-", W-2) .. "+", C.border, C.bg)
  theme.gfill(2, H-1, W-2, 1, " ", C.text, C.bg)
  theme.gset(1, H-1, "|", C.border, C.bg)
  
  local x = 3
  for _, k in ipairs(keys) do
    if x >= W - 4 then break end
    theme.gset(x, H-1, "[" .. k[1] .. "]", C.key, C.bg)
    x = x + #k[1] + 3
    theme.gset(x, H-1, k[2], C.text, C.bg)
    x = x + #k[2] + 2
  end
  
  theme.gset(W, H-1, "|", C.border, C.bg)
  theme.gset(1, H, "+" .. string.rep("-", W-2) .. "+", C.border, C.bg)
end

return theme
