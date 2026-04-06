local define = dofile("/aeon/core/app.lua").define
local shell = dofile("/aeon/shell/shell.lua")

local function count(items)
  return items and #items or 0
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

  term.setCursorPos(1, 1)
  term.clear()

  print("A.E.O.N SERVER CORE")
  print(("Host: %s"):format(runtime.config.hostname or "server-core"))
  print(("Role: %s"):format(tostring(runtime.role.role or "server")))
  print(("Uptime: %ss"):format(uptimeSeconds(runtime)))
  print("")

  print("Services")
  for _, service in ipairs(runtime.services.list()) do
    print(("  %-12s %s"):format(service.name, service.status))
  end

  print("")
  print("Network")
  print(("  Channel: %s"):format(tostring(net and net.config.channel or "offline")))
  print(("  Nodes: %s"):format(tostring(net and count(net.listNodes()) or 0)))

  print("")
  print("System")
  print(("  Tasks: %s"):format(tostring(tasks and count(tasks.list()) or 0)))
  print(("  Sessions: %s"):format(tostring(auth and count(auth.listSessions()) or 0)))
  print("")
  print("Press Enter to open the admin shell.")
  print("Press R to refresh this dashboard.")
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
