local command = {}

function command.run(context, args)
  local target = args[1] or "server-core"
  local net = context.runtime.services.get("net")

  if not net then
    print("network service unavailable")
    return
  end

  local ok, requestId = net.request("system.ping", {
    hostname = context.hostname,
    role = context.role.role or "workstation",
  }, target)

  if not ok then
    print(("ping failed: %s"):format(tostring(requestId)))
    return
  end

  local waitOk, response = net.await(requestId, 3)
  if not waitOk then
    print(("ping timeout: %s"):format(tostring(response)))
    return
  end

  print(("pong from %s role=%s"):format(
    tostring(response.from),
    tostring(response.data and response.data.role or "unknown")
  ))
end

return command
