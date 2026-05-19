-- Single cycle_end listener; controllers register/unregister to avoid duplicates on restart
local event = require("event")

local cycleEnd = {
  handlers = {},
  listening = false,
}

local function dispatch()
  for i = #cycleEnd.handlers, 1, -1 do
    local entry = cycleEnd.handlers[i]
    if entry and entry.fn then
      pcall(entry.fn)
    end
  end
end

local function ensureListener()
  if not cycleEnd.listening then
    event.listen("cycle_end", dispatch)
    cycleEnd.listening = true
  end
end

function cycleEnd.register(owner, fn)
  cycleEnd.unregister(owner)
  table.insert(cycleEnd.handlers, { owner = owner, fn = fn })
  ensureListener()
end

function cycleEnd.unregister(owner)
  for i = #cycleEnd.handlers, 1, -1 do
    if cycleEnd.handlers[i].owner == owner then
      table.remove(cycleEnd.handlers, i)
    end
  end
end

function cycleEnd.clear()
  cycleEnd.handlers = {}
  if cycleEnd.listening then
    event.ignore("cycle_end", dispatch)
    cycleEnd.listening = false
  end
end

return cycleEnd
