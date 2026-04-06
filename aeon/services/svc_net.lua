local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

local function makeMessageId()
  local epoch = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
  local rand = math.random(1000, 9999)
  return ("msg-%s-%s"):format(epoch, rand)
end

local function nowUtc()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function buildMessage(runtime, config, messageType, action, data, target, replyTo)
  return {
    id = makeMessageId(),
    from = runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID()),
    to = target or config.server or "server-core",
    type = messageType or "request",
    action = action,
    data = data or {},
    reply_to = replyTo,
    sent_at = nowUtc(),
  }
end

local service = define({
  name = "net",
  essential = true,
  start = function(context)
    local networkCfg = {}
    if fs.exists("/aeon/etc/network.cfg") then
      networkCfg = dofile("/aeon/etc/network.cfg")
    end
    networkCfg.discovery_interval = networkCfg.discovery_interval or 60
    networkCfg.request_timeout = networkCfg.request_timeout or 5

    local modem = context.registry.find("modem")
    local hostname = context.runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID())
    local pending = {}
    local nodes = {}

    local function recordNode(payload, meta)
      local nodeId = payload.from or "unknown"
      nodes[nodeId] = {
        id = nodeId,
        role = payload.data and payload.data.role or "unknown",
        capabilities = payload.data and payload.data.capabilities or {},
        last_seen = nowUtc(),
        distance = meta and meta.distance or nil,
        channel = meta and meta.channel or nil,
      }
    end

    local function transmit(message)
      if not modem or not modem.object or not modem.object.transmit then
        return false, "modem unavailable"
      end

      if not networkCfg.channel then
        return false, "network channel missing"
      end

      modem.object.transmit(networkCfg.channel, networkCfg.reply_channel or networkCfg.channel, message)
      context.log.info(("net tx %s type=%s to=%s action=%s"):format(
        message.id,
        tostring(message.type),
        tostring(message.to),
        tostring(message.action)
      ))
      return true, message
    end

    local function emitTypedEvent(prefix, action, payload, meta)
      context.emit(events.global(prefix), payload, meta)
      context.emit(events.global(prefix .. "." .. action), payload, meta)
    end

    local function sendNodeHello(target)
      local message = buildMessage(
        context.runtime,
        networkCfg,
        "event",
        "node.hello",
        {
          hostname = hostname,
          role = context.role.role or "workstation",
          capabilities = { "auth", "tasks", "net" },
        },
        target or "*"
      )
      return transmit(message)
    end

    if modem and modem.object and modem.object.open and networkCfg.channel then
      modem.object.open(networkCfg.channel)
      context.log.info(("network channel opened: %s"):format(tostring(networkCfg.channel)))
    else
      context.log.warn("network service started without active modem channel")
    end

    context.on("modem_message", function(event)
      local side = event[2]
      local channel = event[3]
      local replyChannel = event[4]
      local payload = event[5]
      local distance = event[6]

      if networkCfg.channel and channel ~= networkCfg.channel then
        return
      end

      if type(payload) == "table" and payload.id and payload.action then
        if payload.to and payload.to ~= "*" and payload.to ~= hostname then
          return
        end

        context.log.info(
          ("net rx %s type=%s from=%s action=%s side=%s"):format(
            tostring(payload.id),
            tostring(payload.type),
            tostring(payload.from),
            tostring(payload.action),
            tostring(side)
          )
        )

        local meta = {
          side = side,
          channel = channel,
          reply_channel = replyChannel,
          distance = distance,
        }

        recordNode(payload, meta)
        context.emit(events.global("net.message"), payload, meta)

        if payload.type == "request" then
          emitTypedEvent("net.request", payload.action, payload, meta)
        elseif payload.type == "response" then
          pending[payload.reply_to] = payload
          emitTypedEvent("net.response", payload.action, payload, meta)
        elseif payload.type == "error" then
          pending[payload.reply_to] = payload
          context.emit(events.global("net.error"), payload, meta)
        elseif payload.type == "event" then
          emitTypedEvent("net.event", payload.action, payload, meta)
        end

        if payload.type == "request" and payload.action == "system.ping" then
          local response = buildMessage(
            context.runtime,
            networkCfg,
            "response",
            payload.action,
            {
              ok = true,
              hostname = hostname,
              role = context.role.role or "workstation",
              pong = true,
            },
            payload.from,
            payload.id
          )
          transmit(response)
          return
        end

        if payload.type == "request" and payload.action == "node.discover" then
          sendNodeHello(payload.from)
          local response = buildMessage(
            context.runtime,
            networkCfg,
            "response",
            payload.action,
            {
              ok = true,
              hostname = hostname,
              role = context.role.role or "workstation",
            },
            payload.from,
            payload.id
          )
          transmit(response)
          return
        end

        if payload.type == "event" and payload.action == "node.hello" then
          context.emit(events.global("net.node.updated"), payload, meta)
        end
      end
    end)

    context.kernel.spawn("svc:net.discovery", function()
      local interval = tonumber(networkCfg.discovery_interval) or 60
      while true do
        local timer = os.startTimer(interval)
        while true do
          local eventName, timerId = coroutine.yield("timer")
          if timerId == timer then
            break
          end
        end
        sendNodeHello("*")
      end
    end, {
      owner = "net",
      kind = "service",
    })

    sendNodeHello("*")

    return {
      modem = modem,
      config = networkCfg,
      hostname = hostname,
      envelope = function(action, data, target, messageType, replyTo)
        return buildMessage(context.runtime, networkCfg, messageType or "request", action, data, target, replyTo)
      end,
      send = function(action, data, target, messageType)
        local message = buildMessage(context.runtime, networkCfg, messageType or "request", action, data, target)
        return transmit(message)
      end,
      respond = function(requestMessage, data)
        local message = buildMessage(
          context.runtime,
          networkCfg,
          "response",
          requestMessage.action,
          data or {},
          requestMessage.from,
          requestMessage.id
        )
        return transmit(message)
      end,
      fail = function(requestMessage, errorMessage)
        local message = buildMessage(
          context.runtime,
          networkCfg,
          "error",
          requestMessage.action,
          { message = errorMessage or "request failed" },
          requestMessage.from,
          requestMessage.id
        )
        return transmit(message)
      end,
      discover = function()
        local message = buildMessage(context.runtime, networkCfg, "request", "node.discover", {
          hostname = hostname,
          role = context.role.role or "workstation",
        }, "*")
        return transmit(message)
      end,
      listNodes = function()
        local items = {}
        for _, node in pairs(nodes) do
          table.insert(items, node)
        end
        table.sort(items, function(a, b)
          return a.id < b.id
        end)
        return items
      end,
      getNode = function(nodeId)
        return nodes[nodeId]
      end,
      request = function(action, data, target)
        local message = buildMessage(context.runtime, networkCfg, "request", action, data, target)
        local ok, result = transmit(message)
        if not ok then
          return false, result
        end
        return true, message.id
      end,
      await = function(requestId, timeoutSeconds)
        local timeout = tonumber(timeoutSeconds) or networkCfg.request_timeout or 5
        local timer = os.startTimer(timeout)

        while true do
          if pending[requestId] then
            local payload = pending[requestId]
            pending[requestId] = nil
            return true, payload
          end

          local eventName, timerId = coroutine.yield()
          if eventName == "timer" and timerId == timer then
            return false, "timeout"
          end
        end
      end,
    }
  end,
})

return service
