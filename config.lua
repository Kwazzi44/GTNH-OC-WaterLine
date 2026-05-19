local config = {
  enableAutoUpdate = false, -- Выключим автообновление в нашей кастомной версии

  -- Настройки логирования
  logger = {
    level = "debug", -- debug, info, warning, error
    file = "parallel_logs.log",
    printToScreen = true, -- Выводить логи на экран для отладки инициализации
  },

  -- Контроллер главной линии
  lineController = {
    machineName = "multimachine.purificationplant",
    pollInterval = 1, -- Интервал опроса в секундах
  },

  -- Контроллеры тиров
  controllers = {
    t3 = {
      enable = false,
      machineName = "multimachine.purificationunitflocculator",
      transposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      requiredCount = 900000,
      pollInterval = 0.5,
    },
    t4 = {
      enable = false,
      machineName = "multimachine.purificationunitphadjustment",
      hydrochloricAcidTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      sodiumHydroxideTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      pollInterval = 0.5,
    },
    t5 = {
      enable = false,
      machineName = "multimachine.purificationunitplasmaheater",
      plasmaTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      coolantTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      coolantCount = 2000,
      plasmaCount = 100,
      pollInterval = 0.5,
    },
    t6 = {
      enable = false,
      machineName = "multimachine.purificationunituvtreatment",
      transposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      pollInterval = 0.5,
    },
    t7 = {
      enable = false,
      machineName = "multimachine.purificationunitdegasser",
      inertGasTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      superConductorTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      netroniumTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      coolantTransposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      pollInterval = 0.5,
    },
    t8 = {
      enable = false,
      machineName = "multimachine.purificationunitextractor",
      maxQuarkCount = 4,
      transposerAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      subMeInterfaceAddress = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      pollInterval = 0.5,
    }
  }
}

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

return config
