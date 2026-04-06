local define = dofile("/aeon/core/service_contract.lua").define

local service = define({
  name = "log",
  essential = true,
  start = function(context)
    context.log.info("service online")

    return {
      debug = context.logger.debug,
      info = context.logger.info,
      warn = context.logger.warn,
      error = context.logger.error,
    }
  end,
})

return service
