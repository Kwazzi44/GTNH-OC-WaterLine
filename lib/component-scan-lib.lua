-- Incremental component scan (yields to UI between batches; does not block the event loop)
local component = require("component")

local scan = {
  status = "idle",
  machines = {},
  transposers = {},
  interfaces = {},
  queue = nil,
  index = 0,
  total = 0,
}

local function resetResults()
  scan.machines = {}
  scan.transposers = {}
  scan.interfaces = {}
end

function scan.start()
  if scan.status == "running" then
    return false
  end
  resetResults()
  scan.queue = {}
  for addr, typ in component.list() do
    table.insert(scan.queue, { addr = addr, typ = typ })
  end
  scan.index = 0
  scan.total = #scan.queue
  scan.status = "running"
  return true
end

function scan.tick(batchSize)
  if scan.status ~= "running" or not scan.queue then
    return scan.status
  end

  batchSize = batchSize or 4
  local processed = 0

  while processed < batchSize and scan.index < scan.total do
    scan.index = scan.index + 1
    local entry = scan.queue[scan.index]
    local addr, typ = entry.addr, entry.typ

    if typ == "gt_machine" then
      local proxy = component.proxy(addr)
      if proxy then
        local ok, name = pcall(proxy.getName)
        if ok and name then
          table.insert(scan.machines, { address = addr, name = name })
        end
      end
    elseif typ == "transposer" then
      table.insert(scan.transposers, addr)
    elseif typ == "me_interface" then
      table.insert(scan.interfaces, addr)
    end

    processed = processed + 1
  end

  if scan.index >= scan.total then
    scan.status = "done"
    scan.queue = nil
  end

  return scan.status
end

function scan.getProgress()
  if scan.total == 0 then
    return 1, 1
  end
  return scan.index, scan.total
end

function scan.isRunning()
  return scan.status == "running"
end

function scan.isDone()
  return scan.status == "done"
end

function scan.getResults()
  return scan.machines, scan.transposers, scan.interfaces
end

function scan.reset()
  scan.status = "idle"
  scan.queue = nil
  scan.index = 0
  scan.total = 0
  resetResults()
end

-- Run scan to completion while calling tickCallback each frame (for redraw)
function scan.runWithUI(tickCallback, batchSize, eventTimeout)
  scan.start()
  batchSize = batchSize or 4
  eventTimeout = eventTimeout or 0.05

  while scan.isRunning() do
    if tickCallback then
      tickCallback(scan.getProgress())
    end
    scan.tick(batchSize)
    require("event").pull(eventTimeout)
  end

  if tickCallback then
    tickCallback(scan.getProgress())
  end

  return scan.getResults()
end

return scan
