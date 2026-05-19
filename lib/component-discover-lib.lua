-- Component Discover Lib
-- Author: Navatusein
-- License: MIT
-- Version: 1.2

local component = require("component")

---@class TransposerItemStorageDescriptor
---@field side number
---@field slot number

---@class TransposerFluidStorageDescriptor
---@field side number
---@field tank number

---Escape special chars from pattern
---@param text string
---@return string
---@private
local function escapePattern(text)
  local specialChars = "().%+-*?[^$"
  local escapePattern = text:gsub("([%" .. specialChars .. "])", "%%%1")
  return escapePattern
end

---Get sides for check without ignored sides
---@param ignoreSides integer[]
---@return integer[]
---@private
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

-- Cache to store discovered machine proxies and avoid slow getName() calls
local machineCache = nil

---Discover component proxy by address part
---@generic T
---@param address string
---@param name string
---@param type `T`
---@return T
function componentDiscover.discoverProxy(address, name, type)
  local fullAddress = component.get(address, type)

  if fullAddress == nil then
    error("Invalid address of "..type.." "..name)
  end

  return component.proxy(fullAddress, type)
end

local function wrapGtMachine(proxy)
  local cache = {}
  local lastCall = {}
  local cachedMethods = {
    hasWork = true,
    isWorkAllowed = true,
    getWorkProgress = true,
    getWorkMaxProgress = true,
    getSensorInformation = true
  }

  local wrapper = {}
  setmetatable(wrapper, {
    __index = function(_, key)
      local orig = proxy[key]
      if type(orig) ~= "function" then
        return orig
      end

      return function(...)
        local args = {...}
        if args[1] == wrapper then
          table.remove(args, 1)
        end

        if cachedMethods[key] then
          local computer = require("computer")
          local now = computer.uptime()
          if not lastCall[key] or (now - lastCall[key] >= 1.0) then
            local ok, res = pcall(orig, table.unpack(args))
            if ok then
              cache[key] = res
              lastCall[key] = now
            end
          end
          return cache[key]
        else
          return orig(table.unpack(args))
        end
      end
    end
  })
  return wrapper
end

---Discover gt_machine by name
---@param machineName string
---@return gt_machine|nil
function componentDiscover.discoverGtMachine(machineName)
  if not machineCache then
    machineCache = {}
    for key, value in pairs(component.list()) do
      if value == "gt_machine" then
        local machineProxy = component.proxy(key, "gt_machine")
        if machineProxy then
          local ok, name = pcall(machineProxy.getName)
          if ok and name then
            machineCache[name] = wrapGtMachine(machineProxy)
          end
        end
      end
    end
  end

  return machineCache[machineName]
end

---Discover item storages sides connected to transposer
---@param proxy any
---@param ignoreSides any
---@return table
function componentDiscover.discoverTransposerItemStorageSide(proxy, ignoreSides)
  ignoreSides = ignoreSides or {}

  local sides = {}
  local sidesForCheck = getSidesForCheck(ignoreSides)

  for _, side in pairs(sidesForCheck) do
    local stacks = proxy.getAllStacks(side)

    if stacks ~= nil then
      table.insert(sides, side)
    end
  end

  return sides
end

---Discover item storage connected to transposer
---@param proxy transposer
---@param itemLabels string[]
---@param ignoreSides? integer[]
---@return TransposerItemStorageDescriptor[]
---@return string[]
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
  end

  local skipped = {}
  for label in pairs(remainingLabels) do
    table.insert(skipped, label)
  end

  return itemStorageDescriptor, skipped
end

---Discover fluid storage connected to transposer
---@param proxy transposer
---@param fluidNames string[]
---@param ignoreSides? integer[]
---@return TransposerFluidStorageDescriptor[]
---@return string[]
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

        for fluidName in pairs(remainingFluids) do
          if fluid.name ~= nil and string.match(fluid.name, escapePattern(fluidName)) then
            remainingFluids[fluidName] = nil
            fluidStorageDescriptor[fluidName] = {side = side, tank = tankIndex}
            break
          end
        end
      end
    end
  end

  local skipped = {}
  for name in pairs(remainingFluids) do
    table.insert(skipped, name)
  end

  return fluidStorageDescriptor, skipped
end

return componentDiscover