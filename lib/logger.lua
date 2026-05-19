local logger = {}
local lineCount = 0
local memoryLogs = {}
local maxMemoryLogs = 50

function logger.getMemoryLogs()
  return memoryLogs
end

function logger:new(config, prefix)
  local obj = {}
  obj.config = config or { level = "debug", printToScreen = false, file = "waterline_logs.log" }
  obj.prefix = prefix or ""

  local levels = { debug = 1, info = 2, warning = 3, error = 4 }

  local function log(level, message)
    local configLevel = levels[obj.config.level] or 1
    local messageLevel = levels[level] or 1

    if messageLevel >= configLevel then
      local time = os.date("%H:%M:%S")
      local tag = obj.prefix ~= "" and obj.prefix or "System"
      local formattedMessage = string.format("[%s] [%s] [%s] %s", time, level:upper(), tag, message)

      -- Add to memory buffer for GUI
      table.insert(memoryLogs, {
        time = time,
        level = level:upper(),
        tag = tag,
        message = message
      })
      if #memoryLogs > maxMemoryLogs then
        table.remove(memoryLogs, 1)
      end

      if obj.config.printToScreen then
        print(formattedMessage)
      end

      if obj.config.file then
        lineCount = lineCount + 1
        local mode = "a"
        if lineCount >= 250 then
          mode = "w" -- Overwrite when reaching 250 lines
          lineCount = 1
        end

        local f = io.open(obj.config.file, mode)
        if f then
          f:write(formattedMessage .. "\n")
          f:close()
        end
      end
    end
  end

  function obj:debug(message) log("debug", message) end
  function obj:info(message) log("info", message) end
  function obj:warning(message) log("warning", message) end
  function obj:error(message) log("error", message) end

  return obj
end

return logger
