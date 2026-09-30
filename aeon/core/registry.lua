local registry = {
  devices = {},
  byName = {},
  listeners = {},
}

local function normalizeDevice(name)
  local wrapped = peripheral.wrap(name)
  local types = { peripheral.getType(name) }
  if not wrapped or not types[1] then
    return nil
  end
  local entry = {
    name = name,
    type = types[1],
    types = types,
    methods = peripheral.getMethods(name) or {},
    object = wrapped,
  }

  return entry
end

function registry.onRefresh(handler)
  table.insert(registry.listeners, handler)
end

function registry.scan(reason, name)
  registry.devices = {}
  registry.byName = {}

  for _, name in ipairs(peripheral.getNames()) do
    local ok, entry = pcall(normalizeDevice, name)
    if ok and entry then
      table.insert(registry.devices, entry)
      registry.byName[name] = entry
    end
  end

  table.sort(registry.devices, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    end

    return a.type < b.type
  end)

  for _, handler in ipairs(registry.listeners) do
    handler(reason or "refresh", name)
  end

  return registry.devices
end

function registry.list()
  return registry.devices
end

function registry.get(name)
  return registry.byName[name]
end

function registry.find(deviceType)
  for _, device in ipairs(registry.devices) do
    if device.type == deviceType then
      return device
    end
  end

  return nil
end

function registry.findAll(deviceType)
  local matches = {}

  for _, device in ipairs(registry.devices) do
    if device.type == deviceType then
      table.insert(matches, device)
    end
  end

  return matches
end

function registry.refresh(reason, name)
  return registry.scan(reason, name)
end

return registry
