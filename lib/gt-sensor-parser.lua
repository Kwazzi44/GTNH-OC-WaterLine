-- GT Sensor Parser Lib
-- Author: Navatusein
-- License: MIT
-- Version: 1.0

local event = require("event")

local function escapePattern(text)
  local specialChars = "().%+-*?[^$"
  return text:gsub("([%" .. specialChars .. "])", "%%%1")
end

local gtSensorParser = {}

function gtSensorParser:new(gtMachineProxy) 
  local obj = {}
  obj.gtMachineProxy = gtMachineProxy
  obj.sensorData = {}

  function obj:getInformation()
    self.sensorData = self.gtMachineProxy.getSensorInformation()
  end

  function obj:getNumber(line, prefix, postfix)
    local data = self.sensorData[line]
    if data == nil then return nil end

    if prefix ~= nil then
      data = string.gsub(data, escapePattern(prefix), "")
    end
    if postfix ~= nil then
      data = string.gsub(data, escapePattern(postfix), "")
    end

    -- Исправлена кодировка: \194\167 это символ параграфа Minecraft
    data = string.gsub(data, "\194\167.", "")
    data = string.gsub(data, ",", "")
    data = string.match(data, "([%d%.,]+)")

    return tonumber(data)
  end

  function obj:getString(line, prefix, postfix)
    local data = self.sensorData[line]
    if data == nil then return nil end

    if prefix ~= nil then
      data = string.gsub(data, escapePattern(prefix), "")
    end
    if postfix ~= nil then
      data = string.gsub(data, escapePattern(postfix), "")
    end

    data = string.gsub(data, "\194\167.", "")
    return data
  end

  function obj:stringHas(line, value)
    local data = self.sensorData[line]
    if data == nil then return nil end
    return string.match(data, value) ~= nil
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return gtSensorParser