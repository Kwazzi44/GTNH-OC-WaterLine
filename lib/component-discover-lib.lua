-- Component Discover Lib
-- Author: Navatusein
-- License: MIT
-- Version: 1.2

local component = require("component")
local event = require("event")

local function yieldToUi()
  event.pull(0)
end

---Escape special chars from pattern
local function escapePattern(text)
  local specialChars = "().%+-*?[^$"
  local escapePattern = text:gsub("([%" .. specialChars .. "])", "%%%1")
  return escapePattern
end

---Get sides for check without ignored sides
local function getSidesForCheck(ignoreSides)
  local ignoreSet = {}
  for _, side in ipairs(ignoreSides or {}) do
    ignoreSet[side] = true
  end

  local sidesForCheck = {}
  for side = 0, 5 do
    if not ignoreSet[side] then
      table.insert(sidesForCheck, side)
    end
  end

  return sidesForCheck
end

local componentDiscover = {}
local machineCache = nil

function componentDiscover.discoverProxy(address, name, type)
  local fullAddress = component.get(address, type)
  if fullAddress == nil then
    error("Invalid address of "..type.." "..name)
  end
  return component.proxy(fullAddress, type)
end

function componentDiscover.discoverGtMachine(machineName, machineAddress)
  if machineAddress and machineAddress ~= "" then
    local fullAddress = component.get(machineAddress, "gt_machine")
    if fullAddress == nil then
      return nil
    end
    return component.proxy(fullAddress)
  end

  if not machineCache then
    machineCache = {}
    -- Оптимизация: ищем только среди gt_machine
    for key, value in pairs(component.list("gt_machine")) do
      local machineProxy = component.proxy(key)
      if machineProxy then
        local ok, name = pcall(machineProxy.getName)
        if ok and name then
          machineCache[name] = machineProxy
        end
      end
      yieldToUi()
    end
  end
  return machineCache[machineName]
end

function componentDiscover.invalidateMachineCache()
  machineCache = nil
end

function componentDiscover.discoverTransposerItemStorageSide(proxy, ignoreSides)
  ignoreSides = ignoreSides or {}
  local sides = {}
  local sidesForCheck = getSidesForCheck(ignoreSides)

  for _, side in pairs(sidesForCheck) do
    local stacks = proxy.getAllStacks(side)
    if stacks ~= nil then
      table.insert(sides, side)
    end
    yieldToUi()
  end
  return sides
end

function componentDiscover.discoverTransposerItemStorage(proxy, itemLabels, ignoreSides)
  ignoreSides = ignoreSides or {}
  local itemStorageDescriptor = {}
  local sidesForCheck = getSidesForCheck(ignoreSides)

  local remainingLabels = {}
  for _, label in ipairs(itemLabels) do
    remainingLabels[label] = true
  end

  for _, side in pairs(sidesForCheck) do
    local stacks = proxy.getAllStacks(side)
    if stacks ~= nil then
      local slots = stacks.getAll()
      for slotIndex, slot in pairs(slots) do
        if next(slot) ~= nil then
          for itemLabel in pairs(remainingLabels) do
            if slot.label ~= nil and string.match(slot.label, escapePattern(itemLabel)) then
              remainingLabels[itemLabel] = nil
              itemStorageDescriptor[itemLabel] = {side = side, slot = slotIndex + 1}
              break
            end
          end
        end
      end
    end
    yieldToUi()
  end

  local skipped = {}
  for label in pairs(remainingLabels) do
    table.insert(skipped, label)
  end
  return itemStorageDescriptor, skipped
end

function componentDiscover.discoverTransposerFluidStorage(proxy, fluidNames, ignoreSides)
  ignoreSides = ignoreSides or {}
  local fluidStorageDescriptor = {}
  local sidesForCheck = getSidesForCheck(ignoreSides)

  local remainingFluids = {}
  for _, name in ipairs(fluidNames) do
    remainingFluids[name] = true
  end

  for _, side in pairs(sidesForCheck) do
    if proxy.getTankCount(side) ~= 0 then
      local tankCount = proxy.getTankCount(side)
      for tankIndex = 1, tankCount, 1 do
        local fluid = proxy.getFluidInTank(side, tankIndex)
        if fluid and fluid.name then
          for fluidName in pairs(remainingFluids) do
            if string.match(fluid.name, escapePattern(fluidName)) then
              remainingFluids[fluidName] = nil
              fluidStorageDescriptor[fluidName] = {side = side, tank = tankIndex}
              break
            end
          end
        end
        yieldToUi()
      end
    end
    yieldToUi()
  end

  local skipped = {}
  for name in pairs(remainingFluids) do
    table.insert(skipped, name)
  end
  return fluidStorageDescriptor, skipped
end

return componentDiscover