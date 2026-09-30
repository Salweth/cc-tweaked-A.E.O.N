local devices = {}

function devices.hasType(entry, expected)
  for _, value in ipairs(entry.types or { entry.type }) do
    if value == expected then
      return true
    end
  end
  return false
end

function devices.hasMethods(entry, required)
  local methods = {}
  for _, name in ipairs(entry.methods or {}) do
    methods[name] = true
  end
  for _, name in ipairs(required) do
    if not methods[name] or type(entry.object[name]) ~= "function" then
      return false
    end
  end
  return true
end

-- One instance per runtime; the registry remains the physical source of truth.
function devices.create(registry, options)
  options = options or {}
  local drivers, driverIds = {}, {}
  local items, byName, byCapability = {}, {}, {}
  local generation = 0
  local layer = {}

  local function warn(message)
    if options.logger then
      options.logger.warn("[devices] " .. message)
    end
  end

  function layer.registerDriver(driver)
    if type(driver) ~= "table" or type(driver.id) ~= "string" or driver.id == ""
      or type(driver.match) ~= "function" or type(driver.bindCapabilities) ~= "function" then
      return false, "driver requires id, match and bindCapabilities"
    end
    if driverIds[driver.id] then
      return false, "duplicate driver: " .. driver.id
    end
    driverIds[driver.id] = true
    table.insert(drivers, driver)
    return true
  end

  function layer.rebuild(reason, name)
    generation = generation + 1
    local currentGeneration = generation
    items, byName, byCapability = {}, {}, {}
    for _, entry in ipairs(registry.list()) do
      local device = { name = entry.name, type = entry.type, capabilities = {} }
      table.insert(items, device)
      byName[entry.name] = device
      for _, driver in ipairs(drivers) do
        local ok, adapters = pcall(function()
          if not driver.match(entry, devices) then
            return {}
          end
          local result = driver.bindCapabilities(entry)
          assert(type(result) == "table", "capabilities must be a table")
          for capability, api in pairs(result) do
            assert(type(capability) == "string" and capability ~= "" and type(api) == "table",
              "invalid capability adapter")
          end
          return result
        end)
        if not ok then
          warn(("%s on %s: %s"):format(driver.id, entry.name, tostring(adapters)))
        else
          for capability, api in pairs(adapters) do
            if device.capabilities[capability] then
              warn(("duplicate capability %s on %s; keeping first driver"):format(capability, entry.name))
            else
              local provider = {
                name = entry.name, type = entry.type, driver = driver.id, capability = capability,
                call = function(method, ...)
                  if generation ~= currentGeneration then
                    return false, "device handle expired; resolve capability again"
                  end
                  if type(api[method]) ~= "function" then
                    return false, "unsupported method: " .. tostring(method)
                  end
                  return pcall(api[method], ...)
                end,
              }
              device.capabilities[capability] = provider
              byCapability[capability] = byCapability[capability] or {}
              table.insert(byCapability[capability], provider)
            end
          end
        end
      end
    end
    -- Queue through the existing kernel event loop, avoiding recursive task resumes.
    if options.queueEvent then
      options.queueEvent("aeon:devices.changed", reason or "refresh", name, generation)
    end
    return items
  end

  function layer.list()
    return items
  end

  function layer.get(name)
    return byName[name]
  end

  function layer.findCapability(capability)
    local providers = byCapability[capability]
    return providers and providers[1] or nil
  end

  function layer.findAllCapabilities(capability)
    local result = {}
    for _, provider in ipairs(byCapability[capability] or {}) do
      table.insert(result, provider)
    end
    return result
  end

  function layer.refresh()
    registry.refresh()
    return items
  end

  for _, path in ipairs(options.drivers or {
    "/aeon/drivers/modem.lua", "/aeon/drivers/display.lua", "/aeon/drivers/speaker.lua",
  }) do
    local ok, driver = pcall(dofile, path)
    local registered, err = false, driver
    if ok then
      registered, err = layer.registerDriver(driver)
    end
    if not registered then
      warn(("cannot load %s: %s"):format(path, tostring(err)))
    end
  end

  registry.onRefresh(layer.rebuild)
  layer.rebuild("initial")
  return layer
end

return devices
