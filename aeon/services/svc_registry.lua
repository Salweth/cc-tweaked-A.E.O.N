local service = {
  essential = true,
}

function service.start(runtime)
  runtime.logger.info("service registry online")

  runtime.kernel.on("peripheral", function()
    runtime.registry.refresh()
    runtime.logger.info("registry refreshed after peripheral attach")
  end)

  runtime.kernel.on("peripheral_detach", function()
    runtime.registry.refresh()
    runtime.logger.warn("registry refreshed after peripheral detach")
  end)

  return {
    scan = function()
      return runtime.registry.scan()
    end,
    list = function()
      return runtime.registry.list()
    end,
    find = function(deviceType)
      return runtime.registry.find(deviceType)
    end,
    get = function(name)
      return runtime.registry.get(name)
    end,
  }
end

return service
