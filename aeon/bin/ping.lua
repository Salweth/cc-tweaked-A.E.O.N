local command = {}

function command.run(context, args)
  local target = args[1] or "server-core"
  local net = context.runtime.services.get("net")

  if not net then
    print("network service unavailable")
    return
  end

  local ok, result = net.send("system.ping", {
    hostname = context.hostname,
    role = context.role.role or "workstation",
  }, target)

  if not ok then
    print(("ping failed: %s"):format(tostring(result)))
    return
  end

  print(("ping queued: %s -> %s"):format(result.id, tostring(target)))
end

return command
