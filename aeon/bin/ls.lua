local command = {}

function command.run(_context, args)
  local path = args[1] or "."

  if not fs.exists(path) then
    print(("path not found: %s"):format(path))
    return
  end

  if not fs.isDir(path) then
    print(fs.getName(path))
    return
  end

  for _, name in ipairs(fs.list(path)) do
    local child = fs.combine(path, name)
    local suffix = fs.isDir(child) and "/" or ""
    print(name .. suffix)
  end
end

return command
