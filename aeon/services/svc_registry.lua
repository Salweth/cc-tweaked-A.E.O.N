local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

local service = define({
  name = "registry",
  essential = true,
  start = function(context)
    context.log.info("service online")

    context.on("peripheral", function()
      context.registry.refresh()
      context.log.info("registry refreshed after peripheral attach")
      context.emit(events.global("registry.changed"), "attach")
    end)

    context.on("peripheral_detach", function()
      context.registry.refresh()
      context.log.warn("registry refreshed after peripheral detach")
      context.emit(events.global("registry.changed"), "detach")
    end)

    return {
      scan = function()
        return context.registry.scan()
      end,
      list = function()
        return context.registry.list()
      end,
      find = function(deviceType)
        return context.registry.find(deviceType)
      end,
      get = function(name)
        return context.registry.get(name)
      end,
    }
  end,
})

return service
