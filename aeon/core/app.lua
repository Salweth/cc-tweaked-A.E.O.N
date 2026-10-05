local app = {}

local function assertFunction(value, label)
  if type(value) ~= "function" then
    error(label .. " must be a function", 0)
  end
end

-- Foreground app launches share the caller's surface and authentication scope.
function app.create(runtime)
  local ui = dofile("/aeon/core/ui.lua")
  local manager = {}
  function manager.start(definition, options)
    app.define(definition)
    options = options or {}
    local parent = runtime.kernel.getCurrentTask()
    local surface = options.surface or (parent and parent.surface) or "local"
    local sameSurface = parent and parent.surface == surface
    local childRuntime = {}
    for name, value in pairs(runtime) do childRuntime[name] = value end
    local surfaceUI = options.ui or (parent and parent.ui) or runtime.ui
    childRuntime.ui = ui.create(surfaceUI.backend, surfaceUI.theme)
    childRuntime.app_parent = sameSurface and parent.id or nil
    local id = runtime.kernel.createTask("app:" .. definition.name, function()
      local ok, err = pcall(definition.run, childRuntime)
      if definition.stop then
        local stopped, stopErr = pcall(definition.stop, childRuntime)
        if not stopped and ok then ok, err = false, stopErr end
      end
      if not ok then error(err, 0) end
    end, {
      owner = definition.name, kind = "app", parent = parent and parent.id,
      surface = surface,
      ui = childRuntime.ui,
      input = childRuntime.ui.backend.input,
      terminal = childRuntime.ui.backend.terminal,
      auth_scope = sameSurface and parent.auth_scope or nil,
    })
    return id
  end
  function manager.await(id)
    local task = runtime.kernel.getTask(id)
    if not task then return false, "unknown app task" end
    while task.status ~= "dead" and task.status ~= "error" do
      coroutine.yield("aeon:task.finished")
    end
    return task.status == "dead", task.error
  end
  function manager.run(definition, options)
    return manager.await(manager.start(definition, options))
  end
  return manager
end

function app.define(definition)
  if type(definition) ~= "table" then
    error("app definition must be a table", 0)
  end

  if type(definition.name) ~= "string" or definition.name == "" then
    error("app definition requires a non-empty name", 0)
  end

  assertFunction(definition.run, "app.run")

  if definition.stop ~= nil then
    assertFunction(definition.stop, "app.stop")
  end

  return definition
end

return app
