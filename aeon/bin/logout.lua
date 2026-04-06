local command = {}

function command.run(context, _args)
  local auth = context.runtime.services.get("auth")
  if not auth then
    print("auth service unavailable")
    return
  end

  local ok, session = auth.logout()
  if not ok then
    print(("logout failed: %s"):format(tostring(session)))
    return
  end

  print(("logged out: %s"):format(session.username))
end

return command
