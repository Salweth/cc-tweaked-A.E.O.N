local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

local function serviceCapabilities()
  return { "auth", "tasks", "net", "server" }
end

local service = define({
  name = "server",
  essential = true,
  start = function(context)
    local net = context.services.get("net")
    local auth = context.services.get("auth")
    local tasks = context.services.get("tasks")

    context.log.info("service online")

    local function respond(payload, data)
      if not net then
        return false, "network service unavailable"
      end

      return net.respond(payload, data)
    end

    local function fail(payload, message)
      if not net then
        return false, "network service unavailable"
      end

      return net.fail(payload, message)
    end

    context.on(events.global("net.request.system.identity"), function(event)
      local payload = event[2]
      respond(payload, {
        ok = true,
        hostname = context.config.hostname,
        role = context.role.role or "server",
        capabilities = serviceCapabilities(),
      })
    end)

    context.on(events.global("net.request.node.info"), function(event)
      local payload = event[2]
      local taskList = tasks and tasks.list() or {}
      local authSessions = auth and auth.listSessions() or {}

      respond(payload, {
        ok = true,
        hostname = context.config.hostname,
        role = context.role.role or "server",
        services = context.services.list(),
        capabilities = serviceCapabilities(),
        stats = {
          tasks = #taskList,
          sessions = #authSessions,
          started_at = context.runtime.started_at,
        },
      })
    end)

    context.on(events.global("net.request.tasks.list"), function(event)
      local payload = event[2]
      if not tasks then
        fail(payload, "task service unavailable")
        return
      end

      respond(payload, {
        ok = true,
        tasks = tasks.list(),
      })
    end)

    context.on(events.global("net.request.auth.status"), function(event)
      local payload = event[2]
      local authSessions = auth and auth.listSessions() or {}

      respond(payload, {
        ok = true,
        sessions = #authSessions,
        mode = "local-task-session",
      })
    end)

    return {
      capabilities = serviceCapabilities,
      status = function()
        local taskList = tasks and tasks.list() or {}
        local authSessions = auth and auth.listSessions() or {}
        return {
          hostname = context.config.hostname,
          role = context.role.role or "server",
          tasks = #taskList,
          sessions = #authSessions,
        }
      end,
    }
  end,
})

return service
