local command = {}

function command.run(context, _args)
  print(tostring(context.role.role or "workstation"))
end

return command
