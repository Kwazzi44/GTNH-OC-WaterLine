local component = require("component")
local filesystem = require("filesystem")
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")

local registryPath = "/home/registry.lua"

-- Загрузка реестра
local function loadRegistry()
  if filesystem.exists(registryPath) then
    local ok, res = pcall(loadfile(registryPath))
    if ok then return res end
  end
  -- Если файла нет или он битый, возвращаем дефолтную структуру
  return {
    lineController = { machineAddress = nil },
    controllers = {
      t3 = {}, t4 = {}, t5 = {}, t6 = {}, t7 = {}, t8 = {}
    }
  }
end

-- Сохранение реестра
local function saveRegistry(reg)
  local f = io.open(registryPath, "w")
  if f then
    f:write("return {\n")
    f:write("  lineController = {\n")
    f:write(string.format("    machineAddress = %s,\n", reg.lineController.machineAddress and string.format("%q", reg.lineController.machineAddress) or "nil"))
    f:write("  },\n")
    f:write("  controllers = {\n")
    for tier, data in pairs(reg.controllers) do
      f:write(string.format("    %s = {\n", tier))
      for k, v in pairs(data) do
        f:write(string.format("      %s = %s,\n", k, v and string.format("%q", v) or "nil"))
      end
      f:write("    },\n")
    end
    f:write("  }\n")
    f:write("}\n")
    f:close()
    return true
  end
  return false
end

local registry = loadRegistry()

local function clear()
  term.clear()
end

local function printHeader(title)
  print("==========================================")
  print("  " .. title)
  print("==========================================")
end

local function selectMenu(title, options)
  while true do
    clear()
    printHeader(title)
    for i, opt in ipairs(options) do
      print(string.format("%d. %s", i, opt))
    end
    print("\n0. Выход / Назад")
    
    io.write("\nВыберите пункт: ")
    local input = io.read()
    local num = tonumber(input)
    
    if num == 0 then return nil end
    if num and num >= 1 and num <= #options then
      return num
    end
  end
end

-- Сканирование компонентов
local function scanComponents()
  local machines = {}
  local transposers = {}
  
  for addr, type in component.list() do
    if type == "gt_machine" then
      local proxy = component.proxy(addr)
      if proxy then
        local name = proxy.getName()
        table.insert(machines, {address = addr, name = name})
      end
    elseif type == "transposer" then
      table.insert(transposers, addr)
    end
  end
  
  return machines, transposers
end

-- Главный цикл
local function main()
  local machines, transposers = scanComponents()
  
  while true do
    local choice = selectMenu("SETUP - Главное меню", {
      "Выбрать Центральный Контроллер (WPP)",
      "Настроить Тиры (T3 - T8)",
      "Показать текущую конфигурацию"
    })
    
    if not choice then break end
    
    if choice == 1 then
      -- Выбор WPP
      local wppList = {}
      for _, m in ipairs(machines) do
        if m.name == "multimachine.purificationplant" then
          table.insert(wppList, m.address)
        end
      end
      
      if #wppList == 0 then
        print("Машины 'multimachine.purificationplant' не найдены!")
        os.sleep(2)
      else
        local opts = {}
        for i, addr in ipairs(wppList) do
          table.insert(opts, string.format("WPP [%s...]", addr:sub(1, 8)))
        end
        local sel = selectMenu("Выберите WPP", opts)
        if sel then
          registry.lineController.machineAddress = wppList[sel]
          saveRegistry(registry)
          print("Сохранено!")
          os.sleep(1)
        end
      end
      
    elseif choice == 2 then
      -- Настройка Тиров
      local tiers = {
        {key = "t3", name = "T3 (Flocculation)", count = 1, roles = {"transposerAddress"}},
        {key = "t4", name = "T4 (pH Neutralization)", count = 2, roles = {"hydrochloricAcidTransposerAddress", "sodiumHydroxideTransposerAddress"}},
        {key = "t5", name = "T5 (Extreme Temperature)", count = 2, roles = {"plasmaTransposerAddress", "coolantTransposerAddress"}},
        {key = "t6", name = "T6 (High Energy Laser)", count = 1, roles = {"transposerAddress"}},
        {key = "t7", name = "T7 (Residual Degasser)", count = 4, roles = {"inertGasTransposerAddress", "superConductorTransposerAddress", "netroniumTransposerAddress", "coolantTransposerAddress"}},
        {key = "t8", name = "T8 (Absolute Baryonic)", count = 2, roles = {"transposerAddress", "subMeInterfaceAddress"}}
      }
      
      local tierOpts = {}
      for _, t in ipairs(tiers) do
        table.insert(tierOpts, t.name)
      end
      
      local selTier = selectMenu("Выберите Тир для настройки", tierOpts)
      if selTier then
        local tier = tiers[selTier]
        
        for i = 1, tier.count do
          local role = tier.roles[i]
          
          local opts = {}
          for j, addr in ipairs(transposers) do
            local isAssigned = false
            -- Проверяем, не занят ли транспозер
            for tKey, tData in pairs(registry.controllers) do
              for rKey, rAddr in pairs(tData) do
                if rAddr == addr then isAssigned = true end
              end
            end
            
            local statusStr = isAssigned and " [ЗАНЯТ]" or ""
            table.insert(opts, string.format("Transposer [%s...]%s", addr:sub(1, 8), statusStr))
          end
          
          local selTrans = selectMenu("Привязка для роли: " .. role, opts)
          if selTrans then
            registry.controllers[tier.key][role] = transposers[selTrans]
            saveRegistry(registry)
            print("Привязано!")
            os.sleep(1)
          end
        end
      end
      
    elseif choice == 3 then
      clear()
      printHeader("Текущая конфигурация")
      print("WPP: " .. (registry.lineController.machineAddress or "Не выбран"))
      for tier, data in pairs(registry.controllers) do
        print("\n" .. tier:upper() .. ":")
        for k, v in pairs(data) do
          print(string.format("  %s -> %s", k, v or "nil"))
        end
      end
      print("\nНажмите Enter для продолжения...")
      io.read()
    end
  end
end

main()
