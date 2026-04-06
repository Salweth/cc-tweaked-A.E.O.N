local app = {}

local function assertFunction(value, label)
  if type(value) ~= "function" then
    error(label .. " must be a function", 0)
  end
end

function app.define(definition)
  if type(definition) ~= "table" then
    error("app definition must be a table", 0)
  end

  if type(definition.name) ~= "string" or definition.name == "" then
    error("app definition requires a non-empty name", 0)
  end

  assertFunction(definition.run, "app.run")

  if definition.stop ~= nil then
    assertFunction(definition.stop, "app.stop")
  end

  return definition
end

return app
