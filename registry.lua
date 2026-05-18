-- Файл для хранения привязанных адресов (изолирован от обновлений)
local registry = {
  lineController = {
    machineAddress = nil,
  },
  controllers = {
    t3 = {
      transposerAddress = nil,
    },
    t4 = {
      hydrochloricAcidTransposerAddress = nil,
      sodiumHydroxideTransposerAddress = nil,
    },
    t5 = {
      plasmaTransposerAddress = nil,
      coolantTransposerAddress = nil,
    },
    t6 = {
      transposerAddress = nil,
    },
    t7 = {
      inertGasTransposerAddress = nil,
      superConductorTransposerAddress = nil,
      netroniumTransposerAddress = nil,
      coolantTransposerAddress = nil,
    },
    t8 = {
      transposerAddress = nil,
      subMeInterfaceAddress = nil,
    },
  }
}

return registry
