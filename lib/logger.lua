local logger = {}

function logger:new(config, prefix)
  local obj = {}
  obj.config = config or { level = "debug", printToScreen = true, file = "parallel_logs.log" }
  obj.prefix = prefix or ""

  local levels = { debug = 1, info = 2, warning = 3, error = 4 }

  local function log(level, message)
    local configLevel = levels[obj.config.level] or 1
    local messageLevel = levels[level] or 1

    if messageLevel >= configLevel then
      local time = os.date("%H:%M:%S")
      local formattedMessage = string.format("[%s] [%s] %s%s", time, level:upper(), obj.prefix ~= "" and (obj.prefix .. " ") or "", message)

      if obj.config.printToScreen then
        print(formattedMessage)
      end

      if obj.config.file then
        local f = io.open(obj.config.file, "a")
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
