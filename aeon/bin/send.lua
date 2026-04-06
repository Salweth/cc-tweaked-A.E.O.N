local command = {}

function command.run(context, args)
  local target = args[1]
  local action = args[2]
  local payload = args[3]
  local net = context.runtime.services.get("net")

  if not net then
    print("network service unavailable")
    return
  end

  if not target or not action then
    print("usage: send <node> <action> [value]")
    return
  end

  local ok, result = net.send(action, {
    value = payload,
    hostname = context.hostname,
  }, target, "request")

  if not ok then
    print(("send failed: %s"):format(tostring(result)))
    return
  end

  print(("sent %s to %s (%s)"):format(action, target, result.id))
end

return command
