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
    from = runtime.node_id or runtime.hostname or runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID()),
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

    local modem = nil
    local wireless = false
    local instance = nil
    local hostname = context.runtime.hostname or context.runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID())
    local nodeId = context.runtime.node_id or hostname
    local pending = {}
    local nodes = {}

    local function bindModem()
      modem, wireless = nil, false
      local candidates = context.devices.findAllCapabilities("modem")
      -- Policy belongs here: prefer wireless, but retain the wired fallback.
      for _, preferWireless in ipairs({ true, false }) do
        for _, candidate in ipairs(candidates) do
          local ok, value = candidate.call("isWireless")
          if ok and value == preferWireless then
            local opened = candidate.call("open", networkCfg.directory_channel)
            local nodeOpened = candidate.call("open", networkCfg.node_channel)
            if opened and nodeOpened then
              modem, wireless = candidate, value
              break
            end
          end
        end
        if modem then break end
      end
      if instance then
        instance.modem = modem and context.registry.get(modem.name) or nil
        instance.isWireless = wireless
      end
      if not modem then
        context.log.warn("network service started without active modem channel")
      elseif not wireless then
        context.log.warn("wireless modem not found; AEON network isolation is not guaranteed")
      end
    end

    local function recordNode(payload, meta)
      local nodeId = payload.from or "unknown"
      nodes[nodeId] = {
        id = nodeId,
        hostname = payload.data and payload.data.hostname or nodeId,
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
      if not modem then
        return false, "modem unavailable"
      end

      local channel = resolveTargetChannel(message, targetChannel)
      if not channel then
        return false, "network channel missing"
      end

      local ok, err = modem.call("transmit", channel, networkCfg.reply_channel or networkCfg.node_channel, message)
      if not ok then
        return false, err
      end
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
          node_id = nodeId,
          role = context.role.role or "workstation",
          capabilities = { "auth", "tasks", "net" },
          directory_channel = networkCfg.directory_channel,
          node_channel = networkCfg.node_channel,
          wireless = wireless,
        },
        target or "*"
      )
      return transmit(message, networkCfg.directory_channel)
    end

    bindModem()
    context.on(events.global("devices.changed"), function()
      bindModem()
      sendNodeHello("*")
    end)

    context.on("modem_message", function(event)
      local side = event[2]
      local channel = event[3]
      local replyChannel = event[4]
      local payload = event[5]
      local distance = event[6]

      local acceptedChannel = modem and side == modem.name
        and (channel == networkCfg.directory_channel or channel == networkCfg.node_channel)
      if not acceptedChannel then
        return
      end

      if type(payload) == "table" and payload.id and payload.action then
        if payload.from == nodeId then
          return
        end

        if payload.to and payload.to ~= "*" and payload.to ~= hostname and payload.to ~= nodeId then
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

    instance = {
      modem = modem and context.registry.get(modem.name) or nil,
      config = networkCfg,
      hostname = hostname,
      nodeId = nodeId,
      isWireless = wireless,
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
          wireless = wireless,
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
    return instance
  end,
})

return service
