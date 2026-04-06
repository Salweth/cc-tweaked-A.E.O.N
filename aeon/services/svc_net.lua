local service = {
  essential = true,
}

local function makeMessageId()
  local epoch = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
  local rand = math.random(1000, 9999)
  return ("msg-%s-%s"):format(epoch, rand)
end

local function buildMessage(runtime, config, action, data, target)
  return {
    id = makeMessageId(),
    from = runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID()),
    to = target or config.server or "server-core",
    type = "request",
    action = action,
    data = data or {},
  }
end

function service.start(runtime)
  local networkCfg = {}
  if fs.exists("/aeon/etc/network.cfg") then
    networkCfg = dofile("/aeon/etc/network.cfg")
  end

  local modem = runtime.registry.find("modem")
  if modem and modem.object and modem.object.open and networkCfg.channel then
    modem.object.open(networkCfg.channel)
    runtime.logger.info(("network channel opened: %s"):format(tostring(networkCfg.channel)))
  else
    runtime.logger.warn("network service started without active modem channel")
  end

  runtime.kernel.on("modem_message", function(event)
    local side = event[2]
    local channel = event[3]
    local replyChannel = event[4]
    local payload = event[5]
    local distance = event[6]

    if networkCfg.channel and channel ~= networkCfg.channel then
      return
    end

    if type(payload) == "table" and payload.id and payload.action then
      runtime.logger.info(
        ("net rx %s from=%s action=%s side=%s"):format(
          tostring(payload.id),
          tostring(payload.from),
          tostring(payload.action),
          tostring(side)
        )
      )
      runtime.kernel.emit("aeon_net_message", payload, {
        side = side,
        channel = channel,
        reply_channel = replyChannel,
        distance = distance,
      })
    end
  end)

  return {
    modem = modem,
    config = networkCfg,
    envelope = function(action, data, target)
      return buildMessage(runtime, networkCfg, action, data, target)
    end,
    send = function(action, data, target)
      if not modem or not modem.object or not modem.object.transmit then
        return false, "modem unavailable"
      end

      if not networkCfg.channel then
        return false, "network channel missing"
      end

      local message = buildMessage(runtime, networkCfg, action, data, target)
      modem.object.transmit(networkCfg.channel, networkCfg.reply_channel or networkCfg.channel, message)
      runtime.logger.info(("net tx %s to=%s action=%s"):format(message.id, tostring(message.to), tostring(action)))
      return true, message
    end,
  }
end

return service
