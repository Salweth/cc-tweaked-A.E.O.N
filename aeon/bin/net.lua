local command = {}

function command.run(context, _args)
  local net = context.runtime.services.get("net")
  if not net then
    print("network service unavailable")
    return
  end

  print(("hostname: %s"):format(net.hostname or context.hostname))
  print(("channel: %s"):format(tostring(net.config.channel)))
  print(("reply_channel: %s"):format(tostring(net.config.reply_channel)))
  print(("server: %s"):format(tostring(net.config.server)))
  print(("nodes: %s"):format(tostring(#net.listNodes())))
end

return command
