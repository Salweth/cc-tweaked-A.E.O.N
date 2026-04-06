local service = {
  essential = true,
}

function service.start(runtime)
  runtime.logger.info("service log online")

  return {
    debug = runtime.logger.debug,
    info = runtime.logger.info,
    warn = runtime.logger.warn,
    error = runtime.logger.error,
  }
end

return service
