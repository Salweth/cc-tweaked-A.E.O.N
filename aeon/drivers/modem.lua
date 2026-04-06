local driver = {}

local function isWireless(device)
  return device
    and device.object
    and type(device.object.isWireless) == "function"
    and device.object.isWireless()
end

function driver.detect(registry, options)
  options = options or {}
  local matches = registry.findAll("modem")

  if options.preferWireless ~= false then
    for _, device in ipairs(matches) do
      if isWireless(device) then
        return device
      end
    end
  end

  return matches[1]
end

function driver.isWireless(device)
  return isWireless(device)
end

return driver
