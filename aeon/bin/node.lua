local command = {}

function command.run(context, args)
  local net = context.runtime.services.get("net")
  if not net then
    print("network service unavailable")
    return
  end

  local mode = args[1] or "list"

  if mode == "list" then
    local nodes = net.listNodes()
    if #nodes == 0 then
      print("no nodes discovered")
      return
    end

    for _, node in ipairs(nodes) do
      print(("%-16s %-12s last=%s"):format(
        node.id,
        tostring(node.role or "unknown"),
        tostring(node.last_seen)
      ))
    end
    return
  end

  if mode == "discover" then
    local ok, err = net.discover()
    if not ok then
      print(("discover failed: %s"):format(tostring(err)))
      return
    end

    print("discovery broadcast sent")
    return
  end

  if mode == "info" then
    local nodeId = args[2]
    if not nodeId then
      print("usage: node info <id>")
      return
    end

    local node = net.getNode(nodeId)
    if not node then
      print(("unknown node: %s"):format(nodeId))
      return
    end

    print(("id: %s"):format(node.id))
    print(("role: %s"):format(tostring(node.role)))
    print(("last_seen: %s"):format(tostring(node.last_seen)))
    print(("distance: %s"):format(tostring(node.distance)))
    print(("channel: %s"):format(tostring(node.channel)))
    print(("wireless: %s"):format(tostring(node.wireless)))
    print(("capabilities: %s"):format(table.concat(node.capabilities or {}, ", ")))
    return
  end

  print("usage: node [list|discover|info <id>]")
end

return command
