local service = {
  essential = true,
}

local function loadUsers()
  if not fs.exists("/aeon/etc/users.cfg") then
    return {}
  end

  local users = dofile("/aeon/etc/users.cfg")
  return users.users or {}
end

function service.start(runtime)
  local users = loadUsers()
  local current = nil

  runtime.logger.info("service auth online")

  return {
    login = function(username, password)
      local user = users[username]
      if not user or user.password ~= password then
        return false, "invalid credentials"
      end

      current = {
        username = username,
        roles = user.roles or {},
        clearance = user.clearance or 0,
      }

      return true, current
    end,
    logout = function()
      current = nil
    end,
    current = function()
      return current
    end,
  }
end

return service
