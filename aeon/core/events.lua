local events = {}

function events.global(name)
  return "aeon:" .. name
end

function events.private(scope, name)
  return ("aeon:private:%s.%s"):format(scope, name)
end

return events
