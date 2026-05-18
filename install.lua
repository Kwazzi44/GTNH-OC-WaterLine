local component = require("component")
local filesystem = require("filesystem")

if not component.isAvailable("internet") then
  print("Error: Internet card is required!")
  return
end

local internet = require("internet")

-- ЗАМЕНИТЕ ЭТИ ЗНАЧЕНИЯ НА ВАШИ
local repoUrl = "https://raw.githubusercontent.com/Kwazzi44/GTNH-OC-WaterLine/main/"

local files = {
  "config.lua",
  "main.lua",
  "lib/logger.lua",
  "src/line-controller.lua",
  "src/t3-controller.lua",
  "src/t4-controller.lua",
  "src/t5-controller.lua",
  "src/t6-controller.lua",
  "src/t7-controller.lua",
  "src/t8-controller.lua"
}

local function downloadFile(url, path)
  print("Downloading " .. path .. "...")
  
  -- Создаем директории, если их нет
  local dir = path:match("(.+)/[^/]+$")
  if dir then
    filesystem.makeDirectory(dir)
  end
  
  local file, err = io.open(path, "w")
  if not file then
    print("Failed to open file for writing: " .. tostring(err))
    return false
  end
  
  local success, response = pcall(internet.request, url)
  if not success then
    print("Failed to request URL: " .. tostring(response))
    file:close()
    return false
  end
  
  for chunk in response do
    file:write(chunk)
  end
  file:close()
  print("Downloaded " .. path)
  return true
end

print("Starting installation...")

for _, file in ipairs(files) do
  local url = repoUrl .. file
  if not downloadFile(url, file) then
    print("Installation failed at file: " .. file)
    return
  end
end

print("Installation complete! Don't forget to edit config.lua with your addresses.")
