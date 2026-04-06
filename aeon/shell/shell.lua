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

local function makeContext(runtime)
  return {
    runtime = runtime,
    config = runtime.config,
    logger = runtime.logger,
    registry = runtime.registry,
    role = runtime.role,
    hostname = runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID()),
  }
end

local function drawBanner(context)
  term.clear()
  term.setCursorPos(1, 1)
  print("A.E.O.N TERMINAL")
  print(("Host: %s"):format(context.hostname))
  print(("Role: %s"):format(tostring(context.role.role or "workstation")))
  print("Type `help` for available commands.")
  print("")
end

function shellApp.run(runtime)
  local context = makeContext(runtime)
  drawBanner(context)
  context.logger.info("terminal app online")

  while true do
    write(("[%s@%s]$ "):format(tostring(context.role.role or "node"), context.hostname))
    local input = read()
    local parts = split(input or "")
    local name = parts[1]

    if name and name ~= "" then
      table.remove(parts, 1)
      local command, err = loadCommand(name)

      if command then
        local ok, cmdErr = pcall(command.run, context, parts)
        if not ok then
          context.logger.error(cmdErr)
          print(("command failed: %s"):format(tostring(cmdErr)))
        end
      else
        local app, appErr = loadApp(name)
        if not app then
          print(err or appErr or ("unknown command: %s"):format(name))
        else
          local ok, runErr = pcall(app.run, runtime)
          if not ok then
            context.logger.error(runErr)
            print(("app failed: %s"):format(tostring(runErr)))
          end
          drawBanner(context)
        end
      end
    end
  end
end

return shellApp
