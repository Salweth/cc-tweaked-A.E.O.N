local shellApp = {}

local COMMAND_PATHS = {
  "/aeon/bin/%s.lua",
}

local APP_PATHS = {
  "/aeon/apps/%s.lua",
}

local function split(input)
  local parts = {}
  for token in string.gmatch(input, "%S+") do
    table.insert(parts, token)
  end
  return parts
end

local function resolve(paths, name)
  for _, pattern in ipairs(paths) do
    local path = pattern:format(name)
    if fs.exists(path) then
      return path
    end
  end

  return nil
end

local function loadCommand(name)
  local path = resolve(COMMAND_PATHS, name)
  if not path then
    return nil, ("unknown command: %s"):format(name)
  end

  local ok, command = pcall(dofile, path)
  if not ok then
    return nil, ("failed to load %s: %s"):format(name, tostring(command))
  end

  if type(command) ~= "table" or type(command.run) ~= "function" then
    return nil, ("invalid command module: %s"):format(name)
  end

  return command
end

local function loadApp(name)
  local path = resolve(APP_PATHS, name)
  if not path then
    return nil
  end

  local ok, app = pcall(dofile, path)
  if not ok then
    return nil, ("failed to load app %s: %s"):format(name, tostring(app))
  end

  if type(app) ~= "table" or type(app.run) ~= "function" then
    return nil, ("invalid app module: %s"):format(name)
  end

  return app
end

local function makeContext(runtime, console)
  return {
    runtime = runtime,
    config = runtime.config,
    logger = runtime.logger,
    registry = runtime.registry,
    devices = runtime.devices,
    ui = console,
    role = runtime.role,
    hostname = runtime.hostname or runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID()),
  }
end

function shellApp.run(runtime)
  local root = runtime.ui
  if not root.backend.input then return false, "terminal surface requires keyboard input" end
  local width, height = root.size()
  local headerRows = math.min(3, math.max(0, height - 3))
  local console = root.region(1, headerRows + 1, width, height - headerRows)
  local context = makeContext(runtime, console)
  local function session()
    local auth = runtime.services.get("auth")
    return auth and auth.current() or nil
  end
  local function header()
    local user = session()
    local net = runtime.services.get("net")
    local name = (runtime.role.role == "pocket" or runtime.surface_kind == "FIELD") and "FIELD" or "TERMINAL"
    local w = root.size()
    local authLabel = user and ("%s C-%s"):format(user.username, user.clearance or 0) or "ANON"
    local identity
    if w >= 44 then
      identity = ("%s / %s / %s"):format(context.hostname, runtime.role.role or "workstation", authLabel)
    else
      identity = context.hostname:sub(1, math.max(1, w - #authLabel - 3)) .. " / " .. authLabel
    end
    if w >= #identity + 10 then identity = identity .. (net and net.modem and " / LINKED" or " / OFFLINE") end
    for row = 1, headerRows do root.at(1, row, string.rep(" ", w)) end
    root.header(name, identity, headerRows)
  end
  local function layout()
    width, height = root.size()
    headerRows = math.min(3, math.max(0, height - 3))
    console.backend.resize(1, headerRows + 1, width, height - headerRows)
    header()
  end
  console.setEventHandler(function(event)
    if event[1] == "term_resize" then
      layout()
    elseif event[1] == "aeon:auth.login" or event[1] == "aeon:auth.logout"
      or event[1] == "aeon:devices.changed" then header() end
  end)
  root.clear()
  header()
  console.clear()
  console.print("help: commands" .. (runtime.app_parent and " / exit: return" or ""))
  context.logger.info("terminal app online")

  while true do
    layout()
    for _, line in ipairs(runtime.console_messages or {}) do console.print(line) end
    if runtime.console_messages then
      for index = #runtime.console_messages, 1, -1 do runtime.console_messages[index] = nil end
    end
    local input = console.read({ prompt = function()
      local user = session()
      return ("%s@%s > "):format(user and user.username or "ANON", context.hostname)
    end })
    local parts = split(input or "")
    local name = parts[1]

    if name and name ~= "" then
      table.remove(parts, 1)
      if name == "exit" and runtime.app_parent then return end
      local command, err = loadCommand(name)

      if command then
        local ok, cmdErr = pcall(console.withTerminal, command.run, context, parts)
        if not ok then
          context.logger.error(cmdErr)
          console.print(("command failed: %s"):format(tostring(cmdErr)))
        end
      else
        local app, appErr = loadApp(name)
        if not app then
          console.print(appErr or err or ("unknown command: %s"):format(name))
        else
          console.backend.visible(false)
          local launched, ok, runErr = pcall(runtime.apps.run, app, { ui = root })
          if not launched then runErr, ok = ok, false end
          root.clear()
          layout()
          console.backend.visible(true)
          console.backend.redraw()
          if not ok then
            context.logger.error(runErr)
            console.print(("app failed: %s"):format(tostring(runErr)))
          end
        end
      end
    end
  end
end

return shellApp
