local serviceManager = {
  runtime = nil,
  services = {},
  order = {},
}

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
  }

  table.insert(serviceManager.order, name)
end

function serviceManager.start(name)
  local entry = serviceManager.services[name]
  if not entry then
    return false, ("unknown service: %s"):format(tostring(name))
  end

  if entry.status == "running" then
    return true
  end

  local ok, instance = pcall(entry.definition.start, serviceManager.runtime)
  if not ok then
    entry.status = "failed"
    return false, instance
  end

  entry.instance = instance or {}
  entry.status = "running"
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

function serviceManager.list()
  local result = {}

  for _, name in ipairs(serviceManager.order) do
    local entry = serviceManager.services[name]
    table.insert(result, {
      name = entry.name,
      status = entry.status,
    })
  end

  return result
end

return serviceManager
