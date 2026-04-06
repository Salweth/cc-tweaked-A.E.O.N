local packageCore = dofile("/aeon/core/package.lua")

local command = {}

local function currentRole(context)
  return context.role.role or "workstation"
end

function command.run(context, args)
  local mode = args[1] or "list"

  if mode == "list" then
    local items = packageCore.listInstalled()
    if #items == 0 then
      print("no optional apps installed")
      return
    end

    for _, item in ipairs(items) do
      print(("%-22s %s"):format(item.id, tostring(item.version)))
    end
    return
  end

  if mode == "info" then
    local id = args[2]
    if not id then
      print("usage: app info <id>")
      return
    end

    local item = packageCore.getInstalled(id)
    if not item then
      print(("package not installed: %s"):format(id))
      return
    end

    print(("id: %s"):format(item.id))
    print(("name: %s"):format(tostring(item.name)))
    print(("version: %s"):format(tostring(item.version)))
    print(("issuer: %s"):format(tostring(item.issuer)))
    print(("signature: %s"):format(tostring(item.signature)))
    print(("files: %s"):format(tostring(#(item.files or {}))))
    return
  end

  if mode == "install" then
    local mount = args[2]
    if mount == nil or mount == "disk" then
      mount = "/disk"
    end

    local ok, result = packageCore.installFromDisk(currentRole(context), mount)
    if not ok then
      print(("install failed: %s"):format(tostring(result)))
      return
    end

    print(("installed %s %s"):format(
      tostring(result.name or "package"),
      tostring(result.version or "unknown")
    ))
    return
  end

  if mode == "remove" then
    local id = args[2]
    if not id then
      print("usage: app remove <id>")
      return
    end

    local ok, err = packageCore.removeInstalled(id)
    if not ok then
      print(("remove failed: %s"):format(tostring(err)))
      return
    end

    print(("removed %s"):format(id))
    return
  end

  print("usage: app [list|info <id>|install [disk]|remove <id>]")
end

return command
