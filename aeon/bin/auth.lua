local command = {}

function command.run(context, args)
  local auth = context.runtime.services.get("auth")
  if not auth then
    print("auth service unavailable")
    return
  end

  local mode = args[1] or "status"

  if mode == "status" then
    local session = auth.current()
    if not session then
      print("anonymous")
      return
    end

    print(("user: %s"):format(session.username))
    print(("clearance: %s"):format(tostring(session.clearance)))
    print(("roles: %s"):format(table.concat(session.roles or {}, ", ")))
    print(("task: %s"):format(tostring(session.task_id)))
    return
  end

  if mode == "sessions" then
    for _, session in ipairs(auth.listSessions()) do
      print(("%02d %-12s c%s %s"):format(
        session.task_id,
        session.username,
        tostring(session.clearance),
        table.concat(session.roles or {}, ",")
      ))
    end
    return
  end

  print("usage: auth [status|sessions]")
end

return command
