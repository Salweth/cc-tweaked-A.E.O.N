local driver = { id = "cc.monitor" }

function driver.match(entry, helpers)
  return helpers.hasType(entry, "monitor")
    and helpers.hasMethods(entry, { "write", "clear", "setCursorPos", "getSize" })
end

function driver.bindCapabilities(entry)
  return { display = entry.object, monitor = entry.object }
end

function driver.bind(termObject)
  return termObject or term.current()
end

return driver
