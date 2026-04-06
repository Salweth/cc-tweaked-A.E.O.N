local command = {}

function command.run(context, _args)
  local devices = context.registry.list()
  if #devices == 0 then
    print("no peripherals detected")
    return
  end

  for _, device in ipairs(devices) do
    print(("%-18s %s"):format(device.type, device.name))
  end
end

return command
