local config = {
  enableAutoUpdate = false, -- Disable auto-update to avoid overwriting custom changes

  -- Logging settings
  logger = {
    level = "info", -- debug, info, warning, error
    file = "waterline_logs.log",
    printToScreen = false,
  },

  -- Main line controller settings
  lineController = {
    machineName = "multimachine.purificationplant",
    pollInterval = 1,
  },

  -- Tier controllers settings
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

return config