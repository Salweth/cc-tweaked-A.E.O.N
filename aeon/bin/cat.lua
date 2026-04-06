local command = {}

function command.run(_context, args)
  local path = args[1]
  if not path then
    print("usage: cat <path>")
    return
  end

  if not fs.exists(path) or fs.isDir(path) then
    print(("file not found: %s"):format(path))
    return
  end

  local handle = fs.open(path, "r")
  if not handle then
    print(("unable to open: %s"):format(path))
    return
  end

  while true do
    local line = handle.readLine()
    if line == nil then
      break
    end
    print(line)
  end

  handle.close()
end

return command
