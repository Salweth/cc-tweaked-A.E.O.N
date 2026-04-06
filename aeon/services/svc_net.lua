local service = {
  essential = true,
}

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

  return {
    modem = modem,
    config = networkCfg,
  }
end

return service
