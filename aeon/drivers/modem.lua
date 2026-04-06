local driver = {}

function driver.detect(registry)
  return registry.find("modem")
end

return driver
