local bootstrap = {}
local packageCore = nil

local function loadModule(path)
  local ok, result = pcall(dofile, path)
  if not ok then
    error(("failed to load module %s: %s"):format(path, tostring(result)), 0)
  end

  return result
end

local function resolveStartupAppName(config, role)
  if config.startup_app and config.startup_app ~= "" then
    return config.startup_app
  end

  local startupApps = config.startup_apps or {}
  local roleName = role and role.role or "workstation"
  if startupApps[roleName] then
    return startupApps[roleName]
  end

  if roleName == "server" then
    return "server"
  end

  return "terminal"
end

local function loadStartupApp(config, role)
  local appName = resolveStartupAppName(config, role)
  return loadModule(("/aeon/apps/%s.lua"):format(appName)), appName
end

function bootstrap.run()
  local config = loadModule("/aeon/core/config.lua")
  local kernel = loadModule("/aeon/core/kernel.lua")
  local logger = loadModule("/aeon/core/logger.lua")
  local registry = loadModule("/aeon/core/registry.lua")
  local services = loadModule("/aeon/core/service.lua")
  local systemConfig = config.load("/aeon/etc/aeon.cfg")
  local roleConfig = config.load("/aeon/etc/role.cfg")
  local startupApp, startupAppName = loadStartupApp(systemConfig, roleConfig)

  local runtime = {
    started_at = os.epoch and os.epoch("utc") or nil,
    config = systemConfig,
    role = roleConfig,
  }

  runtime.hostname = runtime.config.hostname or os.getComputerLabel() or ("cc-" .. os.getComputerID())
  runtime.node_id = runtime.config.node_id or ("%s-%s"):format(
    runtime.role.role or "node",
    tostring(os.getComputerID())
  )

  logger.init({
    label = "AEON",
    level = runtime.config.log_level or "info",
    console_level = runtime.config.console_log_level or "warn",
    path = "/aeon/var/log/system.log",
  })

  logger.info("bootstrap started")
  registry.scan()

  runtime.kernel = kernel
  runtime.logger = logger
  runtime.registry = registry
  runtime.services = services
  packageCore = packageCore or loadModule("/aeon/core/package.lua")

  logger.info(
    ("machine profile loaded: role=%s hostname=%s"):format(
      tostring(runtime.role.role or "workstation"),
      tostring(runtime.hostname)
    )
  )

  kernel.init(runtime)
  services.init(runtime)
  services.register("log", loadModule("/aeon/services/svc_log.lua"))
  services.register("registry", loadModule("/aeon/services/svc_registry.lua"))
  services.register("auth", loadModule("/aeon/services/svc_auth.lua"))
  services.register("tasks", loadModule("/aeon/services/svc_tasks.lua"))
  services.register("net", loadModule("/aeon/services/svc_net.lua"))

  if runtime.role.role == "server" then
    services.register("server", loadModule("/aeon/services/svc_server.lua"))
  end

  for _, packageEntry in ipairs(packageCore.listInstalled()) do
    local entrypoints = packageEntry.entrypoints or {}
    for _, serviceName in ipairs(entrypoints.services or {}) do
      local path = ("/aeon/services/%s.lua"):format(serviceName)
      if fs.exists(path) then
        services.register(serviceName, loadModule(path))
      end
    end
  end

  services.startEssential()

  for _, packageEntry in ipairs(packageCore.listInstalled()) do
    local entrypoints = packageEntry.entrypoints or {}
    for _, serviceName in ipairs(entrypoints.services or {}) do
      services.start(serviceName)
    end
  end

  kernel.spawn("app:" .. startupAppName, startupApp.run, {
    owner = startupAppName,
    kind = "app",
  })
  kernel.run()
end

return bootstrap
