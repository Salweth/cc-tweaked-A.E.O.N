local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")
local modemDriver = dofile("/aeon/drivers/modem.lua")

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
    from_channel = config.node_channel,
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
    networkCfg.directory_channel = networkCfg.directory_channel or networkCfg.channel or 42
    networkCfg.node_channel = networkCfg.node_channel or networkCfg.reply_channel or (1000 + os.getComputerID())
    networkCfg.reply_channel = networkCfg.reply_channel or networkCfg.node_channel
    networkCfg.address_book = networkCfg.address_book or {}

    local modem = modemDriver.detect(context.registry, {
      preferWireless = true,
    })
    local hostname = context.runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID())
    local pending = {}
    local nodes = {}

    if modem and not modemDriver.isWireless(modem) then
      context.log.warn("wireless modem not found; AEON network isolation is not guaranteed")
    end

    local function recordNode(payload, meta)
      local nodeId = payload.from or "unknown"
      nodes[nodeId] = {
        id = nodeId,
        role = payload.data and payload.data.role or "unknown",
        capabilities = payload.data and payload.data.capabilities or {},
        last_seen = nowUtc(),
        distance = meta and meta.distance or nil,
        channel = payload.from_channel or (meta and meta.reply_channel) or (meta and meta.channel) or nil,
        directory_channel = payload.data and payload.data.directory_channel or nil,
        wireless = payload.data and payload.data.wireless or false,
      }
    end

    local function resolveTargetChannel(message, fallbackChannel)
      if fallbackChannel then
        return fallbackChannel
      end

      if message.to and nodes[message.to] and nodes[message.to].channel then
        return nodes[message.to].channel
      end

      if message.to and networkCfg.address_book[message.to] then
        return networkCfg.address_book[message.to]
      end

      return networkCfg.directory_channel
    end

    local function transmit(message, targetChannel)
      if not modem or not modem.object or not modem.object.transmit then
        return false, "modem unavailable"
      end

      local channel = resolveTargetChannel(message, targetChannel)
      if not channel then
        return false, "network channel missing"
      end

      modem.object.transmit(channel, networkCfg.reply_channel or networkCfg.node_channel, message)
      local line = ("net tx %s type=%s to=%s action=%s channel=%s"):format(
        message.id,
        tostring(message.type),
        tostring(message.to),
        tostring(message.action),
        tostring(channel)
      )
      if message.action == "node.hello" or message.action == "node.discover" then
        context.log.debug(line)
      else
        context.log.info(line)
      end
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
          directory_channel = networkCfg.directory_channel,
          node_channel = networkCfg.node_channel,
          wireless = modemDriver.isWireless(modem),
        },
        target or "*"
      )
      return transmit(message, networkCfg.directory_channel)
    end

    if modem and modem.object and modem.object.open then
      modem.object.open(networkCfg.directory_channel)
      if networkCfg.node_channel ~= networkCfg.directory_channel then
        modem.object.open(networkCfg.node_channel)
      end
      context.log.info(("network channels opened: directory=%s node=%s wireless=%s"):format(
        tostring(networkCfg.directory_channel),
        tostring(networkCfg.node_channel),
        tostring(modemDriver.isWireless(modem))
      ))
    else
      context.log.warn("network service started without active modem channel")
    end

    context.on("modem_message", function(event)
      local side = event[2]
      local channel = event[3]
      local replyChannel = event[4]
      local payload = event[5]
      local distance = event[6]

      local acceptedChannel = channel == networkCfg.directory_channel or channel == networkCfg.node_channel
      if not acceptedChannel then
        return
      end

      if type(payload) == "table" and payload.id and payload.action then
        if payload.from == hostname then
          return
        end

        if payload.to and payload.to ~= "*" and payload.to ~= hostname then
          return
        end

        local line = ("net rx %s type=%s from=%s action=%s side=%s channel=%s"):format(
          tostring(payload.id),
          tostring(payload.type),
          tostring(payload.from),
          tostring(payload.action),
          tostring(side),
          tostring(channel)
        )
        if payload.action == "node.hello" or payload.action == "node.discover" then
          context.log.debug(line)
        else
          context.log.info(line)
        end

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
          transmit(response, payload.from_channel or replyChannel)
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
          transmit(response, payload.from_channel or replyChannel)
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
      isWireless = modemDriver.isWireless(modem),
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
        return transmit(message, requestMessage.from_channel)
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
        return transmit(message, requestMessage.from_channel)
      end,
      discover = function()
        local message = buildMessage(context.runtime, networkCfg, "request", "node.discover", {
          hostname = hostname,
          role = context.role.role or "workstation",
          directory_channel = networkCfg.directory_channel,
          node_channel = networkCfg.node_channel,
          wireless = modemDriver.isWireless(modem),
        }, "*")
        return transmit(message, networkCfg.directory_channel)
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
