local service = {
  essential = true,
}

function service.start(runtime)
  runtime.logger.info("service registry online")

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
  }
end

return service
