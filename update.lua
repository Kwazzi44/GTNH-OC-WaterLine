local REPO = "https://raw.githubusercontent.com/Kwazzi44/GTNH-OC-WaterLine/main"

local component  = require("component")
local filesystem = require("filesystem")
local internet   = require("internet")
local shell      = require("shell")

if not component.isAvailable("internet") then
  io.write("[ERROR] Internet Card not found!\n"); os.exit(1)
end

-- List of files to update (remote source, local destination)
local FILES = {
  { "/config.lua",                      "config.lua"                      },
  { "/registry.lua",                    "registry.lua"                    },
  { "/main.lua",                        "main.lua"                },
  { "/lib/logger.lua",                  "lib/logger.lua"          },
  { "/lib/theme.lua",                   "lib/theme.lua"           },
  { "/lib/gui.lua",                     "lib/gui.lua"             },
  { "/lib/state.lua",                   "lib/state.lua"           },
  { "/lib/log_viewer.lua",              "lib/log_viewer.lua"      },
  { "/lib/state-machine-lib.lua",       "lib/state-machine-lib.lua"       },
  { "/lib/component-discover-lib.lua",  "lib/component-discover-lib.lua"  },
  { "/lib/gt-sensor-parser.lua",        "lib/gt-sensor-parser.lua"        },
  { "/lib/list-lib.lua",                "lib/list-lib.lua"                },
  { "/src/line-controller.lua",         "src/line-controller.lua" },
  { "/src/t3-controller.lua",           "src/t3-controller.lua"   },
  { "/src/t4-controller.lua",           "src/t4-controller.lua"   },
  { "/src/t5-controller.lua",           "src/t5-controller.lua"   },
  { "/src/t6-controller.lua",           "src/t6-controller.lua"   },
  { "/src/t7-controller.lua",           "src/t7-controller.lua"   },
  { "/src/t8-controller.lua",           "src/t8-controller.lua"   },
  { "/update.lua",                      "update.lua"              },
  { "/setup.lua",                       "setup.lua"               },
  { "/version.lua",                     "version.lua"             },
}

local function resolvePath(p)
  if p:sub(1, 1) == "/" then
    return p
  else
    local cwd = shell.getWorkingDirectory() or "/home"
    if cwd:sub(-1) ~= "/" then
      cwd = cwd .. "/"
    end
    return cwd .. p
  end
end

local function mkdirs(dest)
  local absDest = resolvePath(dest)
  local dir = filesystem.path(absDest)
  if dir:sub(-1) == "/" then
    dir = dir:sub(1, -2)
  end
  if dir and dir ~= "" and dir ~= "." and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
end

local function download(url, dest)
  local absDest = resolvePath(dest)
  mkdirs(absDest)

  -- Cache bust query param
  local bust = "?v=" .. tostring(math.random(1000000, 9999999))
  local ok, err = pcall(function()
    local resp, rerr = internet.request(url .. bust)
    if not resp then error(rerr or "connection failed") end
    local f = assert(io.open(absDest, "w"))
    for chunk in resp do f:write(chunk) end
    f:close()
    if type(resp.close) == "function" then
      resp.close()
    end
  end)
  return ok, err
end

io.write("\n==========================================\n")
io.write("  GTNH Water Line Control — UPDATER       \n")
io.write("==========================================\n")
io.write("[NOTE] config.lua and registry.lua are NOT overwritten if they exist.\n\n")

-- Migrate old configuration before starting the update process!
local oldRegistryPath = resolvePath("registry.lua")
local newRegistryPath = resolvePath("registry_data.lua")
if filesystem.exists(oldRegistryPath) and not filesystem.exists(newRegistryPath) then
  local ok, res = pcall(function()
    local f = loadfile(oldRegistryPath)
    if f then return f() end
  end)
  -- If it's a configuration table, copy it to the new path
  if ok and type(res) == "table" and not res.load and not res.save then
    local f = io.open(newRegistryPath, "w")
    if f then
      f:write("return {\n")
      f:write("  lineController = {\n")
      f:write(string.format("    machineAddress = %s,\n", res.lineController and res.lineController.machineAddress and string.format("%q", res.lineController.machineAddress) or "nil"))
      f:write("  },\n")
      f:write("  controllers = {\n")
      for i = 3, 8 do
        local tkey = "t" .. i
        local tdata = res.controllers and res.controllers[tkey] or {}
        f:write(string.format("    %s = {\n", tkey))
        f:write(string.format("      enable = %s,\n", tostring(tdata.enable == true)))
        for k, v in pairs(tdata) do
          if k ~= "enable" then
            f:write(string.format("      %s = %s,\n", k, v and string.format("%q", v) or "nil"))
          end
        end
        f:write("    },\n")
      end
      f:write("  }\n")
      f:write("}\n")
      f:close()
      io.write("[MIGRATED] Old registry settings migrated to registry_data.lua\n\n")
    end
  end
end

local ok_n, fail_n = 0, 0
for _, e in ipairs(FILES) do
  local src_path = e[1]
  local dest_path = e[2]
  local abs_dest = resolvePath(dest_path)
  
  -- Skip overwriting local configurations to avoid wiping user setup
  if (src_path == "/config.lua") and filesystem.exists(abs_dest) then
    io.write(string.format("  [SKIPPED] %-35s (File preserved)\n", dest_path))
  else
    io.write(string.format("  [..] %-35s", dest_path))
    local ok, err = download(REPO .. src_path, dest_path)
    if ok then
      io.write("\r  [OK] " .. dest_path .. "   \n"); ok_n = ok_n + 1
    else
      io.write("\r  [!!] " .. dest_path .. "   \n")
      io.write("       " .. tostring(err) .. "\n"); fail_n = fail_n + 1
    end
  end
  os.sleep(0.1) -- Yield to let network connections close and avoid spamming the connection limit
end

io.write(string.format("\nDone: %d updated, %d failed\n", ok_n, fail_n))
if fail_n == 0 then
  io.write("\nUpdate complete! Run: lua main.lua\n\n")
end
