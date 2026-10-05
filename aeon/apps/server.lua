local define = dofile("/aeon/core/app.lua").define

local function uptime(runtime)
  if not runtime.started_at or not os.epoch then return "UNKNOWN" end
  local seconds = math.max(0, math.floor((os.epoch("utc") - runtime.started_at) / 1000))
  return ("%02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

local function draw(runtime)
  local view = runtime.ui
  local width, height = view.size()
  local net = runtime.services.get("net")
  local auth = runtime.services.get("auth")
  local tasks = runtime.services.get("tasks")
  local peers = net and #net.listNodes() or 0
  local taskList = tasks and tasks.list() or runtime.kernel.listTasks()
  local activeTasks = 0
  for _, task in ipairs(taskList) do
    if task.status ~= "dead" and task.status ~= "error" then activeTasks = activeTasks + 1 end
  end
  local sessions = auth and #auth.listSessions() or 0
  local network = net and net.modem and "ONLINE" or "OFFLINE"
  view.clear()
  local row = view.header("CORE", (runtime.hostname or "UNKNOWN") .. " / " .. (runtime.node_id or "UNKNOWN"),
    height >= 10 and 3 or height >= 5 and 2 or 1)
  if row < height then view.status(row, "NETWORK", network); row = row + 1 end
  if height >= 14 and width >= 24 then
    view.label(row, "PEERS", peers); row = row + 1
    view.label(row, "TASKS", activeTasks); row = row + 1
    view.label(row, "SESSIONS", sessions); row = row + 1
  elseif row < height then
    view.at(1, row, ("P:%d T:%d S:%d"):format(peers, activeTasks, sessions), "muted")
    row = row + 1
  end
  if row < height then view.label(row, "UPTIME", uptime(runtime)); row = row + 1 end
  local services = runtime.services.list()
  if row < height - 1 then
    view.at(1, row, "SERVICES", "accent"); row = row + 1
    local budget = height - row
    local visible = math.min(#services, budget)
    if #services > budget then visible = math.max(0, budget - 1) end
    for index = 1, visible do
      local entry = services[index]
      local state = entry.status == "running" and "ONLINE"
        or entry.status == "failed" and "CRITICAL"
        or entry.status == "starting" and "WARNING" or "OFFLINE"
      view.status(row, entry.name, state); row = row + 1
    end
    if #services > visible and row < height then
      view.at(1, row, ("+%d services"):format(#services - visible), "muted")
    end
  end
  local hint = view.backend.input and "[ENTER] SHELL  [R] REFRESH" or "CORE / DISPLAY ONLY"
  if width < 28 and view.backend.input then hint = "ENTER:shell R:refresh" end
  if height > 1 then view.at(1, height, hint, "muted") end
end

return define({
  name = "server",
  run = function(runtime)
    runtime.logger.info("core surface online")
    local timer = nil
    while true do
      draw(runtime)
      if not timer then timer = os.startTimer(3) end
      while true do
        local eventName, value = runtime.ui.wait()
        if eventName == "timer" and value == timer then timer = nil; break end
        if eventName == "key" and value == keys.enter and runtime.ui.backend.input then
          if os.cancelTimer then os.cancelTimer(timer) end
          local ok, err = runtime.apps.run(dofile("/aeon/apps/terminal.lua"))
          if not ok then runtime.logger.warn("terminal returned: " .. tostring(err)) end
          timer = nil
          break
        end
        if eventName == "term_resize" or eventName == "monitor_resize"
          or eventName == "aeon:devices.changed" or eventName == "aeon:net.node.updated"
          or eventName:match("^aeon:service%.") or eventName:match("^aeon:auth%.")
          or (eventName == "char" and (value == "r" or value == "R")) then break end
      end
    end
  end,
})
