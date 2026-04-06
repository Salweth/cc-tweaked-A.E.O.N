local permissions = {}

local function getAuth(runtime)
  if not runtime or not runtime.services then
    return nil, "runtime unavailable"
  end

  local auth = runtime.services.get("auth")
  if not auth then
    return nil, "auth service unavailable"
  end

  return auth
end

function permissions.hasRole(runtime, role, taskId)
  local auth, err = getAuth(runtime)
  if not auth then
    return false, err
  end

  return auth.hasRole(role, taskId)
end

function permissions.hasClearance(runtime, level, taskId)
  local auth, err = getAuth(runtime)
  if not auth then
    return false, err
  end

  return auth.hasClearance(level, taskId)
end

function permissions.requireRole(runtime, role, taskId)
  local auth, err = getAuth(runtime)
  if not auth then
    return false, err
  end

  return auth.requireRole(role, taskId)
end

function permissions.requireClearance(runtime, level, taskId)
  local auth, err = getAuth(runtime)
  if not auth then
    return false, err
  end

  return auth.requireClearance(level, taskId)
end

return permissions
