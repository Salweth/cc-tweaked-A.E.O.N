local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

local function loadUsers()
  if not fs.exists("/aeon/etc/users.cfg") then
    return {}
  end

  local users = dofile("/aeon/etc/users.cfg")
  return users.users or {}
end

local function listHasValue(items, expected)
  for _, item in ipairs(items or {}) do
    if item == expected then
      return true
    end
  end

  return false
end

local function snapshotSession(taskId, username, user)
  return {
    task_id = taskId,
    username = username,
    roles = user.roles or {},
    clearance = user.clearance or 0,
  }
end

local service = define({
  name = "auth",
  essential = true,
  start = function(context)
    local users = loadUsers()
    local sessions = {}

    local function currentTaskId()
      local task = context.kernel.getCurrentTask()
      return task and task.id or 0
    end

    local function getSession(taskId)
      return sessions[taskId or currentTaskId()]
    end

    local function fail(reason, metadata)
      context.log.warn(reason)
      context.emit(events.global("auth.failed"), reason, metadata or {})
      return false, reason
    end

    context.log.info("service online")

    return {
      login = function(username, password, taskId)
        local user = users[username]
        if not user or user.password ~= password then
          return fail("invalid credentials", {
            username = username,
            task_id = taskId or currentTaskId(),
          })
        end

        local session = snapshotSession(taskId or currentTaskId(), username, user)
        sessions[session.task_id] = session
        context.emit(events.global("auth.login"), session)
        context.log.info(("login success user=%s task=%s"):format(session.username, tostring(session.task_id)))
        return true, session
      end,
      logout = function(taskId)
        local session = getSession(taskId)
        if not session then
          return false, "no active session"
        end

        sessions[session.task_id] = nil
        context.emit(events.global("auth.logout"), session)
        context.log.info(("logout user=%s task=%s"):format(session.username, tostring(session.task_id)))
        return true, session
      end,
      current = function(taskId)
        return getSession(taskId)
      end,
      hasRole = function(role, taskId)
        local session = getSession(taskId)
        if not session then
          return false
        end

        return listHasValue(session.roles, role)
      end,
      hasClearance = function(level, taskId)
        local session = getSession(taskId)
        if not session then
          return false
        end

        return (session.clearance or 0) >= level
      end,
      requireRole = function(role, taskId)
        if not getSession(taskId) then
          return false, "authentication required"
        end

        if not listHasValue(getSession(taskId).roles, role) then
          return false, ("role required: %s"):format(role)
        end

        return true
      end,
      requireClearance = function(level, taskId)
        local session = getSession(taskId)
        if not session then
          return false, "authentication required"
        end

        if (session.clearance or 0) < level then
          return false, ("clearance %s required"):format(tostring(level))
        end

        return true
      end,
      listSessions = function()
        local result = {}
        for _, session in pairs(sessions) do
          table.insert(result, session)
        end
        table.sort(result, function(a, b)
          return a.task_id < b.task_id
        end)
        return result
      end,
    }
  end,
})

return service
