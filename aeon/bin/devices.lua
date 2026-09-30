local command = {}

function command.run(context, _args)
  local devices = context.registry.list()
  if #devices == 0 then
    print("no peripherals detected")
    return
  end

  for _, device in ipairs(devices) do
    print(("%-18s %s"):format(device.type, device.name))
    local logical = context.devices and context.devices.get(device.name)
    local capabilities = {}
    for name in pairs(logical and logical.capabilities or {}) do
      table.insert(capabilities, name)
    end
    table.sort(capabilities)
    if #capabilities > 0 then
      print("  " .. table.concat(capabilities, ", "))
    end
  end
end

return command
