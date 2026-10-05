local kernel = {
  runtime = nil,
  tasks = {},
  listeners = {},
  nextTaskId = 0,
  running = false,
  currentTask = nil,
  foreground = {},
  dispatching = false,
}

local function packEvent(...)
  return { n = select("#", ...), ... }
end

local function unpackEvent(event)
  return table.unpack(event, 1, event.n or #event)
end

local function normalizeFilter(value)
  if value == nil or type(value) == "string" then
    return value
  end

  error("kernel tasks must yield nil or an event name", 0)
end

local function resumeTask(task, event)
  local previousTask = kernel.currentTask
  local display = kernel.runtime and kernel.runtime.display
  local previousTerminal = display and display.current()
  if display and task.terminal then display.activate(task.terminal) end
  local ok
  local filterOrError

  task.status = "running"

  if event then
    kernel.currentTask = task
    ok, filterOrError = coroutine.resume(task.co, unpackEvent(event))
  else
    kernel.currentTask = task
    ok, filterOrError = coroutine.resume(task.co)
  end
  kernel.currentTask = previousTask
  if display then
    task.terminal = display.current()
    display.activate(previousTerminal)
  end

  if ok and coroutine.status(task.co) ~= "dead" then
    ok, filterOrError = pcall(normalizeFilter, filterOrError)
  end

  if not ok then
    task.status = "error"
    task.error = filterOrError
    if kernel.runtime and kernel.runtime.logger then
      kernel.runtime.logger.error(("task %s crashed: %s"):format(task.name, tostring(filterOrError)))
    end
  elseif coroutine.status(task.co) == "dead" then
    task.status = "dead"
    task.filter = nil
  else
    task.status = "waiting"
    task.filter = filterOrError
  end
  if task.status == "dead" or task.status == "error" then
    if task.surface and kernel.foreground[task.surface] == task.id then
      kernel.foreground[task.surface] = task.previousForeground
    end
    os.queueEvent("aeon:task.finished", task.id, task.status, task.error)
  end
end

local INPUT_EVENTS = {
  char = true, key = true, key_up = true, paste = true,
  mouse_click = true, mouse_drag = true, mouse_up = true, mouse_scroll = true,
  monitor_touch = true, terminate = true,
}

local function shouldReceive(task, event)
  if task.status == "dead" or task.status == "error" or task.status == "running" then
    return false
  end

  local eventName = event[1]
  if task.surface then
    if kernel.foreground[task.surface] ~= task.id then return false end
    if INPUT_EVENTS[eventName] and task.input == false then return false end
  end
  return task.filter == nil or task.filter == eventName or eventName == "terminate"
end

function kernel.init(runtime)
  kernel.runtime = runtime
  kernel.tasks = {}
  kernel.listeners = {}
  kernel.nextTaskId = 0
  kernel.running = false
  kernel.currentTask = nil
  kernel.foreground = {}
  kernel.dispatching = false
end

function kernel.createTask(name, fn, options)
  kernel.nextTaskId = kernel.nextTaskId + 1
  options = options or {}

  local task = {
    id = kernel.nextTaskId,
    name = name or ("task-" .. kernel.nextTaskId),
    co = coroutine.create(fn),
    filter = nil,
    status = "ready",
    error = nil,
    owner = options.owner or name or ("task-" .. kernel.nextTaskId),
    kind = options.kind or "background",
    parent = options.parent,
    surface = options.surface,
    input = options.input,
    ui = options.ui,
    auth_scope = options.auth_scope or kernel.nextTaskId,
    terminal = options.terminal or (kernel.runtime.display and kernel.runtime.display.current()),
  }

  if task.surface then
    task.previousForeground = kernel.foreground[task.surface]
    kernel.foreground[task.surface] = task.id
  end

  table.insert(kernel.tasks, task)
  resumeTask(task, nil)
  return task.id
end

function kernel.spawn(name, fn, options)
  return kernel.createTask(name, function()
    fn(kernel.runtime)
  end, options)
end

function kernel.on(eventName, handler)
  if not kernel.listeners[eventName] then
    kernel.listeners[eventName] = {}
  end

  table.insert(kernel.listeners[eventName], handler)
end

function kernel.emit(eventName, ...)
  if kernel.currentTask or kernel.dispatching then
    os.queueEvent(eventName, ...)
    return
  end
  local event = packEvent(eventName, ...)
  kernel.dispatch(event)
end

function kernel.dispatch(event)
  local previousDispatching = kernel.dispatching
  kernel.dispatching = true
  local eventName = event[1]
  local listeners = kernel.listeners[eventName] or {}
  local count = #kernel.tasks

  for _, handler in ipairs(listeners) do
    local ok, err = pcall(handler, event, kernel.runtime)
    if not ok and kernel.runtime and kernel.runtime.logger then
      kernel.runtime.logger.error(("listener %s failed: %s"):format(eventName, tostring(err)))
    end
  end

  -- Newly launched apps must not receive the Enter/key event that launched them.
  for index = 1, count do
    local task = kernel.tasks[index]
    if shouldReceive(task, event) then
      resumeTask(task, event)
    end
  end
  kernel.dispatching = previousDispatching
end

function kernel.run()
  kernel.running = true

  while kernel.running do
    local event = packEvent(os.pullEventRaw())
    kernel.dispatch(event)
  end
end

function kernel.stop()
  kernel.running = false
end

function kernel.listTasks()
  local items = {}

  for _, task in ipairs(kernel.tasks) do
    table.insert(items, {
      id = task.id,
      name = task.name,
      status = task.status,
      filter = task.filter,
      owner = task.owner,
      kind = task.kind,
      parent = task.parent,
      surface = task.surface,
      auth_scope = task.auth_scope,
    })
  end

  return items
end

function kernel.getCurrentTask()
  return kernel.currentTask
end

function kernel.getTask(id)
  for _, task in ipairs(kernel.tasks) do
    if task.id == id then return task end
  end
end

function kernel.isForeground(id)
  local task = kernel.getTask(id)
  return task and (not task.surface or kernel.foreground[task.surface] == id)
end

return kernel
