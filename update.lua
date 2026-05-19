local REPO = "https://raw.githubusercontent.com/Kwazzi44/GTNH-OC-WaterLine/main"

local component  = require("component")
local filesystem = require("filesystem")
local internet   = require("internet")

if not component.isAvailable("internet") then
  io.write("[ERROR] Internet Card not found!\n"); os.exit(1)
end

-- Список файлов для скачивания (откуда, куда)
local FILES = {
  { "/config.lua",              "/home/config.lua"              },
  { "/registry.lua",            "/home/registry.lua"            },
  { "/main.lua",                "/home/main.lua"                },
  { "/lib/logger.lua",          "/home/lib/logger.lua"          },
  { "/lib/theme.lua",           "/home/lib/theme.lua"           },
  { "/lib/gui.lua",             "/home/lib/gui.lua"             },
  { "/lib/state.lua",           "/home/lib/state.lua"           },
  { "/lib/log_viewer.lua",      "/home/lib/log_viewer.lua"      },
  { "/src/line-controller.lua", "/home/src/line-controller.lua" },
  { "/src/t3-controller.lua",   "/home/src/t3-controller.lua"   },
  { "/src/t4-controller.lua",   "/home/src/t4-controller.lua"   },
  { "/src/t5-controller.lua",   "/home/src/t5-controller.lua"   },
  { "/src/t6-controller.lua",   "/home/src/t6-controller.lua"   },
  { "/src/t7-controller.lua",   "/home/src/t7-controller.lua"   },
  { "/src/t8-controller.lua",   "/home/src/t8-controller.lua"   },
  { "/update.lua",              "/home/update.lua"              },
  { "/setup.lua",               "/home/setup.lua"               },
  { "/install.lua",             "/home/install.lua"             },
}

local function mkdirs(dest)
  local dir = filesystem.path(dest)
  if dir and dir ~= "/" and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
end

local function download(url, dest)
  mkdirs(dest)

  -- Анти-кеш (bust)
  local bust = "?v=" .. tostring(math.random(1000000, 9999999))
  local ok, err = pcall(function()
    local resp = internet.request(url .. bust)
    local f = assert(io.open(dest, "w"))
    for chunk in resp do f:write(chunk) end
    f:close()
  end)
  return ok, err
end

io.write("\n==========================================\n")
io.write("  GTNH Water Line Control — UPDATER       \n")
io.write("==========================================\n")
io.write("[NOTE] config.lua and registry.lua are NOT overwritten if they exist.\n\n")

local ok_n, fail_n = 0, 0
for _, e in ipairs(FILES) do
  local src_path = e[1]
  local dest_path = e[2]
  
  -- Проверяем, если это конфиг или реестр и они уже есть - пропускаем
  if (src_path == "/config.lua" or src_path == "/registry.lua") and filesystem.exists(dest_path) then
    io.write(string.format("  [SKIPPED] %-35s (File preserved)\n", dest_path))
  else
    io.write(string.format("  [..] %-35s", dest_path))
    local ok, err = download(REPO .. src_path, dest_path)
    if ok then
      io.write("\r  [OK] " .. dest_path .. "\n"); ok_n = ok_n + 1
    else
      io.write("\r  [!!] " .. dest_path .. "\n")
      io.write("       " .. tostring(err) .. "\n"); fail_n = fail_n + 1
    end
  end
end

io.write(string.format("\nDone: %d updated, %d failed\n", ok_n, fail_n))
if fail_n == 0 then
  io.write("\nUpdate complete! Run: lua /home/main.lua\n\n")
end
