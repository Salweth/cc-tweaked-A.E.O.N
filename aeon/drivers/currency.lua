local driver = {}

local SUPPORTED_TYPES = {
  "cclc:card_reader",
  "cclc:cardreader",
}

function driver.detect(registry)
  for _, deviceType in ipairs(SUPPORTED_TYPES) do
    local device = registry.find(deviceType)
    if device then
      return device
    end
  end

  return nil
end

return driver
