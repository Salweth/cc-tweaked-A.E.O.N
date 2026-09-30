local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

local service = define({
  name = "registry",
  essential = true,
  start = function(context)
    context.log.info("service online")

    context.on("peripheral", function(event)
      context.registry.refresh("attach", event[2])
      context.log.info("registry refreshed after peripheral attach")
      os.queueEvent(events.global("registry.changed"), "attach", event[2])
    end)

    context.on("peripheral_detach", function(event)
      context.registry.refresh("detach", event[2])
      context.log.warn("registry refreshed after peripheral detach")
      os.queueEvent(events.global("registry.changed"), "detach", event[2])
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
