local command = {}

function command.run(context, _args)
  local auth = context.runtime.services.get("auth")
  local user = auth and auth.current() or nil

  if not user then
    print("anonymous")
    return
  end

  print(("%s [clearance %s]"):format(user.username, tostring(user.clearance)))
end

return command
