local bootstrap = {}

local function loadModule(path)
  local ok, result = pcall(dofile, path)
  if not ok then
    error(("failed to load module %s: %s"):format(path, tostring(result)), 0)
  end

  return result
end

function bootstrap.run()
  local config = loadModule("/aeon/core/config.lua")
  local logger = loadModule("/aeon/core/logger.lua")
  local registry = loadModule("/aeon/core/registry.lua")
  local services = loadModule("/aeon/core/service.lua")
  local shell = loadModule("/aeon/shell/shell.lua")

  local runtime = {
    started_at = os.epoch and os.epoch("utc") or nil,
    config = config.load("/aeon/etc/aeon.cfg"),
    role = config.load("/aeon/etc/role.cfg"),
  }

  logger.init({
    label = "AEON",
    level = runtime.config.log_level or "info",
    path = "/aeon/var/log/system.log",
  })

  logger.info("bootstrap started")
  registry.scan()

  runtime.logger = logger
  runtime.registry = registry
  runtime.services = services

  logger.info(
    ("machine profile loaded: role=%s hostname=%s"):format(
      tostring(runtime.role.role or "workstation"),
      tostring(runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID()))
    )
  )

  services.init(runtime)
  services.register("registry", loadModule("/aeon/services/svc_registry.lua"))
  services.register("auth", loadModule("/aeon/services/svc_auth.lua"))
  services.register("net", loadModule("/aeon/services/svc_net.lua"))
  services.startEssential()

  shell.run(runtime)
end

return bootstrap
