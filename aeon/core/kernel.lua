local kernel = {
  runtime = nil,
  tasks = {},
  listeners = {},
  nextTaskId = 0,
  running = false,
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
  local ok
  local filterOrError

  if event then
    ok, filterOrError = coroutine.resume(task.co, unpackEvent(event))
  else
    ok, filterOrError = coroutine.resume(task.co)
  end

  if not ok then
    task.status = "error"
    task.error = filterOrError
    if kernel.runtime and kernel.runtime.logger then
      kernel.runtime.logger.error(("task %s crashed: %s"):format(task.name, tostring(filterOrError)))
    end
    return
  end

  if coroutine.status(task.co) == "dead" then
    task.status = "dead"
    task.filter = nil
    return
  end

  task.status = "waiting"
  task.filter = normalizeFilter(filterOrError)
end

local function shouldReceive(task, event)
  if task.status == "dead" or task.status == "error" then
    return false
  end

  local eventName = event[1]
  return task.filter == nil or task.filter == eventName or eventName == "terminate"
end

function kernel.init(runtime)
  kernel.runtime = runtime
  kernel.tasks = {}
  kernel.listeners = {}
  kernel.nextTaskId = 0
  kernel.running = false
end

function kernel.createTask(name, fn)
  kernel.nextTaskId = kernel.nextTaskId + 1

  local task = {
    id = kernel.nextTaskId,
    name = name or ("task-" .. kernel.nextTaskId),
    co = coroutine.create(fn),
    filter = nil,
    status = "ready",
    error = nil,
  }

  table.insert(kernel.tasks, task)
  resumeTask(task, nil)
  return task.id
end

function kernel.spawn(name, fn)
  return kernel.createTask(name, function()
    fn(kernel.runtime)
  end)
end

function kernel.on(eventName, handler)
  if not kernel.listeners[eventName] then
    kernel.listeners[eventName] = {}
  end

  table.insert(kernel.listeners[eventName], handler)
end

function kernel.emit(eventName, ...)
  local event = packEvent(eventName, ...)
  kernel.dispatch(event)
end

function kernel.dispatch(event)
  local eventName = event[1]
  local listeners = kernel.listeners[eventName] or {}

  for _, handler in ipairs(listeners) do
    local ok, err = pcall(handler, event, kernel.runtime)
    if not ok and kernel.runtime and kernel.runtime.logger then
      kernel.runtime.logger.error(("listener %s failed: %s"):format(eventName, tostring(err)))
    end
  end

  for _, task in ipairs(kernel.tasks) do
    if shouldReceive(task, event) then
      resumeTask(task, event)
    end
  end
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
    })
  end

  return items
end

return kernel
