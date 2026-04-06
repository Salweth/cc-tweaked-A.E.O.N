local command = {}

function command.run(context, _args)
  local services = context.runtime.services.list()
  for _, service in ipairs(services) do
    print(("%-12s %s"):format(service.status, service.name))
  end
end

return command
