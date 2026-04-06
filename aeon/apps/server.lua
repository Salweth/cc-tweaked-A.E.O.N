local define = dofile("/aeon/core/app.lua").define
local shell = dofile("/aeon/shell/shell.lua")

local function count(items)
  return items and #items or 0
end

local function pushLine(lines, value)
  table.insert(lines, value)
end

local function uptimeSeconds(runtime)
  if not runtime.started_at or not os.epoch then
    return 0
  end

  return math.floor((os.epoch("utc") - runtime.started_at) / 1000)
end

local function draw(runtime)
  local services = runtime.services
  local net = services.get("net")
  local auth = services.get("auth")
  local tasks = services.get("tasks")
  local width, height = term.getSize()
  local lines = {}
  local serviceItems = runtime.services.list()

  term.setCursorPos(1, 1)
  term.clear()

  pushLine(lines, "A.E.O.N SERVER CORE")
  pushLine(lines, ("Host: %s"):format(runtime.hostname or runtime.config.hostname or "server"))
  pushLine(lines, ("Node: %s"):format(runtime.node_id or "unknown"))
  pushLine(lines, ("Role: %s  Uptime: %ss"):format(
    tostring(runtime.role.role or "server"),
    uptimeSeconds(runtime)
  ))
  pushLine(lines, ("Net: dir=%s node=%s peers=%s"):format(
    tostring(net and net.config.directory_channel or "offline"),
    tostring(net and net.config.node_channel or "offline"),
    tostring(net and count(net.listNodes()) or 0)
  ))
  pushLine(lines, ("Sys: tasks=%s sessions=%s"):format(
    tostring(tasks and count(tasks.list()) or 0),
    tostring(auth and count(auth.listSessions()) or 0)
  ))
  pushLine(lines, "Services:")

  local reservedLines = 9
  local serviceBudget = math.max(1, height - reservedLines)
  local visibleServices = math.min(#serviceItems, serviceBudget)
  for index = 1, visibleServices do
    local service = serviceItems[index]
    pushLine(lines, ("  %-12s %s"):format(service.name, service.status))
  end
  if #serviceItems > visibleServices then
    pushLine(lines, ("  ... +%d more"):format(#serviceItems - visibleServices))
  end

  pushLine(lines, "")
  pushLine(lines, "Enter: shell   R: refresh")

  local start = math.max(1, #lines - height + 1)
  for lineIndex = start, #lines do
    local text = lines[lineIndex]
    if #text > width then
      text = text:sub(1, width)
    end
    print(text)
  end
end

local app = define({
  name = "server",
  run = function(runtime)
    runtime.logger.info("server app online")

    local wakeEvents = {
      ["timer"] = true,
      ["aeon:service.started"] = true,
      ["aeon:service.stopped"] = true,
      ["aeon:service.failed"] = true,
      ["aeon:tasks.changed"] = true,
      ["aeon:auth.login"] = true,
      ["aeon:auth.logout"] = true,
      ["aeon:net.node.updated"] = true,
    }

    while true do
      draw(runtime)
      local timer = os.startTimer(3)

      while true do
        local eventName, timerId = coroutine.yield()
        if eventName == "timer" and timerId == timer then
          break
        end

        if eventName == "key" and timerId == keys.enter then
          shell.run(runtime)
          break
        end

        if eventName == "char" and (timerId == "r" or timerId == "R") then
          break
        end

        if wakeEvents[eventName] then
          break
        end
      end
    end
  end,
})

return app
