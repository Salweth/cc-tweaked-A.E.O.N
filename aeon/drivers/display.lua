local driver = {}

function driver.bind(termObject)
  return termObject or term.current()
end

return driver
