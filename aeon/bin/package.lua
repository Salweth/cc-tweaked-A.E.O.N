local packageCore = dofile("/aeon/core/package.lua")

local command = {}

function command.run(_context, args)
  local mode = args[1] or "list"
  local roleName = _context and _context.role and _context.role.role or "server"

  if mode == "list" then
    local items = packageCore.listAvailable()
    if #items == 0 then
      print("no packages available")
      return
    end

    for _, item in ipairs(items) do
      print(("%-22s %s"):format(item.id, tostring(item.version)))
    end
    return
  end

  if mode == "inspect" then
    local mount = args[2]
    if mount == nil or mount == "disk" then
      mount = "/disk"
    end

    local ok, result = packageCore.inspectDisk(mount)
    if not ok then
      print(("inspect failed: %s"):format(tostring(result)))
      return
    end

    local manifest = result.manifest
    print(("id: %s"):format(tostring(manifest.id)))
    print(("name: %s"):format(tostring(manifest.name)))
    print(("version: %s"):format(tostring(manifest.version)))
    print(("issuer: %s"):format(tostring(manifest.issuer)))
    print(("signature: %s"):format(tostring(manifest.signature)))
    print(("files: %s"):format(tostring(#(manifest.files or {}))))
    return
  end

  if mode == "write" then
    local id = args[2]
    local mount = args[3]
    if not id then
      print("usage: package write <id> [disk]")
      return
    end

    if mount == nil or mount == "disk" then
      mount = "/disk"
    end

    local ok, manifest = packageCore.writeToDisk(id, mount)
    if not ok then
      print(("write failed: %s"):format(tostring(manifest)))
      return
    end

    print(("wrote %s %s to %s"):format(
      tostring(manifest.name or manifest.id),
      tostring(manifest.version or "unknown"),
      tostring(mount)
    ))
    return
  end

  if mode == "install" then
    local id = args[2]
    if not id then
      print("usage: package install <id>")
      return
    end

    local ok, result = packageCore.installFromRepo(roleName, id)
    if not ok then
      print(("install failed: %s"):format(tostring(result)))
      return
    end

    print(("installed %s %s locally"):format(
      tostring(result.name or id),
      tostring(result.version or "unknown")
    ))
    print("reboot required to activate service entrypoints")
    return
  end

  print("usage: package [list|inspect [disk]|write <id> [disk]|install <id>]")
end

return command
