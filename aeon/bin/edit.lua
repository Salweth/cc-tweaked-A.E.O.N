local command = {}

function command.run(_context, args)
  local path = args[1]
  if not path then
    print("usage: edit <path>")
    return
  end

  if not shell or type(shell.run) ~= "function" then
    print("craftos shell unavailable")
    return
  end

  shell.run("edit", path)
end

return command
