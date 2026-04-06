local command = {}

function command.run(_context, _args)
  os.reboot()
end

return command
