local serviceManager = {
  runtime = nil,
  services = {},
  order = {},
}

local events = dofile("/aeon/core/events.lua")

local function buildContext(runtime, entry)
  return {
    runtime = runtime,
    kernel = runtime.kernel,
    logger = runtime.logger,
    registry = runtime.registry,
    services = serviceManager,
    config = runtime.config,
    role = runtime.role,
    service = entry,
    on = function(eventName, handler)
      runtime.kernel.on(eventName, handler)
    end,
    emit = function(eventName, ...)
      runtime.kernel.emit(eventName, ...)
    end,
    emitPrivate = function(eventName, ...)
      runtime.kernel.emit(events.private(entry.name, eventName), ...)
    end,
    log = {
      debug = function(message) runtime.logger.debug(("[%s] %s"):format(entry.name, tostring(message))) end,
      info = function(message) runtime.logger.info(("[%s] %s"):format(entry.name, tostring(message))) end,
      warn = function(message) runtime.logger.warn(("[%s] %s"):format(entry.name, tostring(message))) end,
      error = function(message) runtime.logger.error(("[%s] %s"):format(entry.name, tostring(message))) end,
    }
  }
end

function serviceManager.init(runtime)
  serviceManager.runtime = runtime
  serviceManager.services = {}
  serviceManager.order = {}
end

function serviceManager.register(name, definition)
  serviceManager.services[name] = {
    name = name,
    status = "registered",
    definition = definition,
    instance = nil,
    context = nil,
  }

  table.insert(serviceManager.order, name)

  if serviceManager.runtime and serviceManager.runtime.kernel then
    serviceManager.runtime.kernel.emit(events.global("service.registered"), name)
  end
end

function serviceManager.start(name)
  local entry = serviceManager.services[name]
  if not entry then
    return false, ("unknown service: %s"):format(tostring(name))
  end

  if entry.status == "running" then
    return true
  end

  entry.status = "starting"
  entry.context = buildContext(serviceManager.runtime, entry)
  entry.context.emit(events.global("service.starting"), name)

  local ok, instance = pcall(entry.definition.start, entry.context)
  if not ok then
    entry.status = "failed"
    entry.context.emit(events.global("service.failed"), name, instance)
    return false, instance
  end

  entry.instance = instance or {}
  entry.status = "running"
  entry.context.emit(events.global("service.started"), name)
  return true
end

function serviceManager.stop(name)
  local entry = serviceManager.services[name]
  if not entry then
    return false, ("unknown service: %s"):format(tostring(name))
  end

  if entry.status ~= "running" then
    return true
  end

  if entry.definition.stop then
    local ok, err = pcall(entry.definition.stop, entry.context, entry.instance)
    if not ok then
      entry.status = "failed"
      entry.context.emit(events.global("service.failed"), name, err)
      return false, err
    end
  end

  entry.status = "stopped"
  entry.context.emit(events.global("service.stopped"), name)
  return true
end

function serviceManager.startEssential()
  for _, name in ipairs(serviceManager.order) do
    local entry = serviceManager.services[name]
    if entry and entry.definition.essential ~= false then
      local ok, err = serviceManager.start(name)
      if not ok and serviceManager.runtime and serviceManager.runtime.logger then
        serviceManager.runtime.logger.error(("service %s failed: %s"):format(name, tostring(err)))
      end
    end
  end
end

function serviceManager.get(name)
  local entry = serviceManager.services[name]
  return entry and entry.instance or nil
end

function serviceManager.registerListener(eventName, handler)
  if serviceManager.runtime and serviceManager.runtime.kernel then
    serviceManager.runtime.kernel.on(eventName, handler)
  end
end

function serviceManager.list()
  local result = {}

  for _, name in ipairs(serviceManager.order) do
    local entry = serviceManager.services[name]
    table.insert(result, {
      name = entry.name,
      status = entry.status,
      essential = entry.definition.essential,
    })
  end

  return result
end

return serviceManager
