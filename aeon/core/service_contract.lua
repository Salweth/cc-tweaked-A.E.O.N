local contract = {}

local function assertFunction(value, label)
  if type(value) ~= "function" then
    error(label .. " must be a function", 0)
  end
end

function contract.define(definition)
  if type(definition) ~= "table" then
    error("service definition must be a table", 0)
  end

  if type(definition.name) ~= "string" or definition.name == "" then
    error("service definition requires a non-empty name", 0)
  end

  assertFunction(definition.start, "service.start")

  if definition.stop ~= nil then
    assertFunction(definition.stop, "service.stop")
  end

  if definition.essential == nil then
    definition.essential = true
  end

  return definition
end

return contract
