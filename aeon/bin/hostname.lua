local command = {}

function command.run(context, _args)
  print(context.hostname)
end

return command
