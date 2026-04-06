local registry = {
  devices = {}
}

local function normalizeDevice(name)
  local wrapped = peripheral.wrap(name)
  local entry = {
    name = name,
    type = peripheral.getType(name),
    methods = peripheral.getMethods(name) or {},
    object = wrapped,
  }

  return entry
end

function registry.scan()
  registry.devices = {}

  for _, name in ipairs(peripheral.getNames()) do
    table.insert(registry.devices, normalizeDevice(name))
  end

  table.sort(registry.devices, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    end

    return a.type < b.type
  end)

  return registry.devices
end

function registry.list()
  return registry.devices
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

return registry
