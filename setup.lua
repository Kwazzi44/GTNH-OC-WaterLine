-- setup.lua
local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local unicode = require("unicode")
local theme = require("lib.theme")
local registry = require("registry")

local gpu = component.isAvailable("gpu") and component.gpu or nil
if not gpu then io.write("GPU not found!\n"); return end

theme.init(gpu)
local W, H = theme.getRes()
local C = theme.C

local regData = registry.load()

local LEFT_W = 24
local RX = LEFT_W + 3

local function gset(x, y, text, fg, bg) theme.gset(x, y, text, fg, bg) end
local function gfill(x, y, w, h, ch, fg, bg) theme.gfill(x, y, w, h, ch, fg, bg) end
local function pad(s, n) return theme.pad(s, n) end

local function drawFrame()
  gfill(1, 1, W, H, " ", C.text, C.bg)
  theme.drawHeader("GTNH WATER LINE - SETUP", "Hardware Registration Wizard")
  
  -- Left border divider
  for row = 4, H-3 do
    gset(LEFT_W + 1, row, "|", C.border, C.bg)
  end
  gset(LEFT_W + 1, H-2, "+", C.border, C.bg)
end

local function drawFooter(keys)
  theme.drawFooter(keys)
end

local function clearRight()
  gfill(LEFT_W + 2, 4, W - LEFT_W - 2, H - 6, " ", C.text, C.bg)
end

local function drawMenu(items, sel)
  gset(2, 5, "MENU", C.dim, C.bg)
  gset(2, 6, string.rep("-", LEFT_W - 2), C.border, C.bg)
  for i, item in ipairs(items) do
    local y = 6 + i
    if i == sel then
      gfill(2, y, LEFT_W - 1, 1, " ", C.sel_fg, C.sel_bg)
      gset(3, y, item.label, C.sel_fg, C.sel_bg)
    else
      gfill(2, y, LEFT_W - 1, 1, " ", C.text, C.bg)
      gset(3, y, item.label, C.text, C.bg)
    end
  end
end

-- Scanning helpers
local function scanMachinesAndTransposers()
  local machines = {}
  local transposers = {}
  local interfaces = {}
  
  for addr, type in component.list() do
    if type == "gt_machine" then
      local proxy = component.proxy(addr)
      if proxy then
        local ok, name = pcall(proxy.getName)
        if ok and name then
          table.insert(machines, { address = addr, name = name })
        end
      end
    elseif type == "transposer" then
      table.insert(transposers, addr)
    elseif type == "me_interface" then
      table.insert(interfaces, addr)
    end
  end
  return machines, transposers, interfaces
end

-- Interactive single item selector from list
local function selectFromList(title, list, itemFormatter)
  local sel = 1
  local scroll = 1
  local viewH = H - 10
  
  while true do
    clearRight()
    gset(RX, 4, "--- " .. title:upper() .. " ---", C.title, C.bg)
    gset(RX, 5, string.rep("-", W - LEFT_W - 5), C.border, C.bg)
    
    if #list == 0 then
      gset(RX, 7, "No compatible components found on network.", C.warn, C.bg)
      gset(RX, 9, "Press Enter to return...", C.dim, C.bg)
      drawFooter({{"B", "Back"}})
      while true do
        local _, _, _, code = event.pull("key_down")
        if code == 28 or code == keyboard.keys.b or code == 1 or code == 14 then return nil end
      end
    end
    
    for i = 0, viewH - 1 do
      local idx = scroll + i
      local y = 7 + i
      if idx <= #list then
        local item = list[idx]
        local label = itemFormatter(item, idx)
        label = pad(label, W - LEFT_W - 6)
        if idx == sel then
          gfill(RX, y, W - LEFT_W - 4, 1, " ", C.sel_fg, C.sel_bg)
          gset(RX, y, label, C.sel_fg, C.sel_bg)
        else
          gfill(RX, y, W - LEFT_W - 4, 1, " ", C.text, C.bg)
          gset(RX, y, label, C.text, C.bg)
        end
      else
        gfill(RX, y, W - LEFT_W - 4, 1, " ", C.text, C.bg)
      end
    end
    
    drawFooter({{"Up/Dn", "Select"}, {"Enter", "Confirm"}, {"B", "Cancel"}})
    local ev, _, _, code = event.pull("key_down")
    if ev == "key_down" then
      if code == 200 then -- Up
        if sel > 1 then
          sel = sel - 1
          if sel < scroll then scroll = sel end
        end
      elseif code == 208 then -- Down
        if sel < #list then
          sel = sel + 1
          if sel >= scroll + viewH then scroll = sel - viewH + 1 end
        end
      elseif code == 28 then -- Enter
        return list[sel]
      elseif code == keyboard.keys.b or code == 14 or code == 1 then -- B / Backspace / Esc
        return nil
      end
    end
  end
end

-- Configure WPP Controller
local function configureWPP()
  clearRight()
  gset(RX, 4, "--- CONFIGURE MAIN LINE (WPP) ---", C.title, C.bg)
  gset(RX, 5, string.rep("-", W - LEFT_W - 5), C.border, C.bg)
  
  local current = regData.lineController.machineAddress or "Not bound (autodetect)"
  gset(RX, 7, "Current WPP Address:", C.text, C.bg)
  gset(RX, 8, current, current == "Not bound (autodetect)" and C.warn or C.ok, C.bg)
  
  gset(RX, 10, "1. Bind new WPP address from network", C.text, C.bg)
  gset(RX, 11, "2. Reset to autodetect mode", C.text, C.bg)
  gset(RX, 13, "Press [B] to return", C.dim, C.bg)
  
  drawFooter({{"1", "Bind WPP"}, {"2", "Reset"}, {"B", "Back"}})
  
  while true do
    local ev, _, _, code = event.pull("key_down")
    if ev == "key_down" then
      if code == 2 then -- '1'
        local machines = scanMachinesAndTransposers()
        local wppCandidates = {}
        for _, m in ipairs(machines) do
          if m.name == "multimachine.purificationplant" then
            table.insert(wppCandidates, m)
          end
        end
        local selected = selectFromList("Select WPP Machine", wppCandidates, function(item)
          return string.format("%s... (%s)", item.address:sub(1, 12), item.name)
        end)
        if selected then
          regData.lineController.machineAddress = selected.address
          return true
        end
        return false
      elseif code == 3 then -- '2'
        regData.lineController.machineAddress = nil
        return true
      elseif code == keyboard.keys.b or code == 14 or code == 1 then -- B / Backspace / Esc
        return false
      end
    end
  end
end

-- Tiers Configuration Submenu
local function configureTiers()
  local tiers = {
    { key = "t3", label = "T3 Flocculation", roles = { { key = "transposerAddress", name = "Polyaluminium Transposer" } } },
    { key = "t4", label = "T4 pH Adjustment", roles = { { key = "hydrochloricAcidTransposerAddress", name = "HCl Acid Transposer" }, { key = "sodiumHydroxideTransposerAddress", name = "NaOH Dust Transposer" } } },
    { key = "t5", label = "T5 Extreme Temp", roles = { { key = "plasmaTransposerAddress", name = "Helium Plasma Transposer" }, { key = "coolantTransposerAddress", name = "Super Coolant Transposer" } } },
    { key = "t6", label = "T6 UV Treatment", roles = { { key = "transposerAddress", name = "Lens Transposer" } } },
    { key = "t7", label = "T7 Degasser", roles = { { key = "inertGasTransposerAddress", name = "Inert Gas Transposer" }, { key = "superConductorTransposerAddress", name = "Supercond Transposer" }, { key = "netroniumTransposerAddress", name = "Neutronium Transposer" }, { key = "coolantTransposerAddress", name = "Super Coolant Transposer" } } },
    { key = "t8", label = "T8 Subatomic Extr", roles = { { key = "transposerAddress", name = "Quark Transposer" }, { key = "subMeInterfaceAddress", name = "Sub-AE ME Interface", isInterface = true } } }
  }
  
  local sel = 1
  while true do
    clearRight()
    gset(RX, 4, "--- CONFIGURE WATER LINE TIERS ---", C.title, C.bg)
    gset(RX, 5, string.rep("-", W - LEFT_W - 5), C.border, C.bg)
    
    for idx, t in ipairs(tiers) do
      local y = 7 + (idx - 1) * 2
      local treg = regData.controllers[t.key] or {}
      local status = treg.enable and "[ENABLED]" or "[DISABLED]"
      local scol = treg.enable and C.ok or C.dim
      
      local label = string.format("%d. %-20s %s", idx, t.label, status)
      if idx == sel then
        gfill(RX, y, W - LEFT_W - 4, 1, " ", C.sel_fg, C.sel_bg)
        gset(RX, y, label, C.sel_fg, C.sel_bg)
      else
        gfill(RX, y, W - LEFT_W - 4, 1, " ", C.text, C.bg)
        gset(RX, y, label, C.text, C.bg)
        gset(RX + 22, y, status, scol, C.bg)
      end
    end
    
    gset(RX, H-5, "Press Enter to configure selected tier.", C.dim, C.bg)
    drawFooter({{"Up/Dn", "Select"}, {"Enter", "Configure"}, {"B", "Back"}})
    
    local ev, _, _, code = event.pull("key_down")
    if ev == "key_down" then
      if code == 200 then -- Up
        if sel > 1 then sel = sel - 1 end
      elseif code == 208 then -- Down
        if sel < #tiers then sel = sel + 1 end
      elseif code == 28 then -- Enter
        -- Configure selected tier
        local tier = tiers[sel]
        local exitTier = false
        while not exitTier do
          clearRight()
          gset(RX, 4, "--- CONFIG: " .. tier.label:upper() .. " ---", C.title, C.bg)
          gset(RX, 5, string.rep("-", W - LEFT_W - 5), C.border, C.bg)
          
          local treg = regData.controllers[tier.key] or {}
          local enLabel = treg.enable and "Enabled: YES" or "Enabled: NO"
          gset(RX, 7, "1. Toggle State: " .. enLabel, C.text, C.bg)
          gset(RX + 17, 7, treg.enable and "YES" or "NO", treg.enable and C.ok or C.ring_down, C.bg)
          
          gset(RX, 9, "Transposers / Interfaces:", C.dim, C.bg)
          local y = 10
          for rIdx, role in ipairs(tier.roles) do
            local addr = treg[role.key] or "Not configured"
            local acol = (addr == "Not configured") and C.ring_down or C.ok
            local rowLabel = string.format("   %d) %-25s: %s", rIdx + 1, role.name, addr:sub(1, 10) .. "...")
            gset(RX, y, rowLabel, C.text, C.bg)
            gset(RX + 3 + 27, y, addr:sub(1, 12), acol, C.bg)
            y = y + 1
          end
          
          gset(RX, H-5, "Press number to select or B to back.", C.dim, C.bg)
          drawFooter({{"1", "Toggle State"}, {"2-9", "Bind Hardware"}, {"B", "Back"}})
          
          local ev2, _, _, code2 = event.pull("key_down")
          if ev2 == "key_down" then
            if code2 == 2 then -- '1'
              treg.enable = not treg.enable
              regData.controllers[tier.key] = treg
            elseif code2 >= 3 and code2 <= 1 + #tier.roles + 1 then -- '2' - '9'
              local rIdx = code2 - 2
              local role = tier.roles[rIdx]
              if role then
                local _, transposers, interfaces = scanMachinesAndTransposers()
                local list = role.isInterface and interfaces or transposers
                
                local selected = selectFromList("Select for " .. role.name, list, function(item) return item end)
                if selected then
                  treg[role.key] = selected
                  regData.controllers[tier.key] = treg
                end
              end
            elseif code2 == keyboard.keys.b or code2 == 14 or code2 == 1 then -- B / Backspace / Esc
              exitTier = true
            end
          end
        end
      elseif code == keyboard.keys.b or code == 14 or code == 1 then -- B / Backspace / Esc
        break
      end
    end
  end
end

-- Show Registry Details
local function showRegistry()
  clearRight()
  gset(RX, 4, "--- CONFIGURATION REGISTRY ---", C.title, C.bg)
  gset(RX, 5, string.rep("-", W - LEFT_W - 5), C.border, C.bg)
  
  local y = 7
  gset(RX, y, "WPP Address: " .. (regData.lineController.machineAddress or "AUTODETECT"), C.text, C.bg)
  y = y + 2
  
  for i = 3, 8 do
    local tkey = "t" .. i
    local treg = regData.controllers[tkey] or {}
    local status = treg.enable and "ENABLED" or "DISABLED"
    local scol = treg.enable and C.ok or C.dim
    gset(RX, y, string.format("T%d (%s):", i, status), C.title, C.bg)
    gset(RX + 9, y, status, scol, C.bg)
    y = y + 1
    
    local hasItems = false
    for k, v in pairs(treg) do
      if k ~= "enable" then
        gset(RX, y, string.format("  %-16s: %s", k, tostring(v):sub(1, 15) .. "..."), C.text, C.bg)
        y = y + 1
        hasItems = true
      end
    end
    if not hasItems then
      gset(RX, y, "  (No transposers required/configured)", C.dim, C.bg)
      y = y + 1
    end
    y = y + 1
    if y >= H - 4 then break end
  end
  
  gset(RX, H-3, "Press any key to return...", C.dim, C.bg)
  drawFooter({{"Any Key", "Back"}})
  event.pull("key_down")
end

local MENU_ITEMS = {
  { label = "1. Main WPP Config", fn = configureWPP },
  { label = "2. Configure Tiers", fn = configureTiers },
  { label = "3. Show Registry  ", fn = showRegistry },
  { label = "4. Save & Exit   ", fn = function() registry.save(regData); return "exit" end }
}

local function run()
  drawFrame()
  local sel = 1
  
  while true do
    drawMenu(MENU_ITEMS, sel)
    drawFooter({{"Up/Dn", "Move"}, {"Enter", "Select"}, {"B", "Cancel"}})
    
    local ev, _, _, code = event.pull("key_down")
    if ev == "key_down" then
      if code == 200 then -- Up
        if sel > 1 then sel = sel - 1 end
      elseif code == 208 then -- Down
        if sel < #MENU_ITEMS then sel = sel + 1 end
      elseif code == 28 then -- Enter
        local res = MENU_ITEMS[sel].fn()
        if res == "exit" then break end
        drawFrame()
      elseif code == keyboard.keys.b or code == 1 then -- B / Esc
        break
      end
    end
  end
  
  -- Restore screen
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
end

local ok, err = pcall(run)
if not ok then
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF2244)
  gpu.fill(1, 1, W, H, " ")
  gpu.set(1, 1, "SETUP UTILITY CRASHED:")
  gpu.set(1, 3, tostring(err))
  gpu.set(1, H, "Press any key to exit...")
  event.pull("key_down")
end
