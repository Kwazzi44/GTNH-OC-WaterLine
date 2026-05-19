-- GT Sensor Parser Lib
-- Author: Navatusein
-- License: MIT
-- Version: 1.1

local function escapePattern(text)
  local specialChars = "().%+-*?[^$"
  return text:gsub("([%" .. specialChars .. "])", "%%%1")
end

local function stripFormatting(data)
  if data == nil then
    return nil
  end
  data = string.gsub(data, "\194\167.", "")
  return data
end

local gtSensorParser = {}

function gtSensorParser:new(gtMachineProxy)
  local obj = {}
  obj.gtMachineProxy = gtMachineProxy
  obj.sensorData = {}

  local lastQueryTime = 0
  local cacheDuration = 1.0

  function obj:getInformation()
    local computer = require("computer")
    local now = computer.uptime()
    if now - lastQueryTime >= cacheDuration or #self.sensorData == 0 then
      local ok, res = pcall(function() return self.gtMachineProxy.getSensorInformation() end)
      if ok and res then
        self.sensorData = res
        lastQueryTime = now
      end
    end
  end

  function obj:findLine(prefixPattern)
    if prefixPattern == nil then
      return nil, nil
    end
    local pattern = escapePattern(prefixPattern)

    for line, data in ipairs(self.sensorData) do
      if data and string.find(data, pattern) then
        return line, data
      end
    end

    return nil, nil
  end

  function obj:getRawLine(line)
    return self.sensorData[line]
  end

  function obj:getNumber(line, prefix, postfix, altPrefixes)
    local prefixes = { prefix }
    if altPrefixes then
      for _, p in ipairs(altPrefixes) do
        table.insert(prefixes, p)
      end
    end

    for _, p in ipairs(prefixes) do
      if p ~= nil then
        local useLine = line
        local data = self.sensorData[useLine]

        if data == nil or not string.find(data, escapePattern(p)) then
          useLine, data = self:findLine(p)
        end

        if data ~= nil then
          data = string.gsub(data, escapePattern(p), "")
          if postfix ~= nil then
            data = string.gsub(data, escapePattern(postfix), "")
          end

          data = stripFormatting(data)
          data = string.gsub(data, ",", "")
          local num = string.match(data, "([%d%.,]+)")
          local value = tonumber(num)
          if value ~= nil then
            return value
          end
        end
      end
    end

    return nil
  end

  function obj:getString(line, prefix, postfix, altPrefixes)
    local prefixes = { prefix }
    if altPrefixes then
      for _, p in ipairs(altPrefixes) do
        table.insert(prefixes, p)
      end
    end

    for _, p in ipairs(prefixes) do
      if p == nil then
        -- skip nil prefix entries
      else
        local useLine = line
        local data = self.sensorData[useLine]

        if data == nil or not string.find(data, escapePattern(p)) then
          useLine, data = self:findLine(p)
        end

        if data ~= nil then
          data = string.gsub(data, escapePattern(p), "")
          if postfix ~= nil then
            data = string.gsub(data, escapePattern(postfix), "")
          end
          return stripFormatting(data)
        end
      end
    end

    return nil
  end

  function obj:stringHas(line, value)
    local data = self.sensorData[line]
    if data == nil then
      return nil
    end
    return string.match(data, value) ~= nil
  end

  function obj:stringHasAny(line, values)
    for _, value in ipairs(values) do
      if self:stringHas(line, value) then
        return true
      end
    end
    return false
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return gtSensorParser
