local command = {}

function command.run(context, args)
  local username = args[1]
  if not username then
    write("username: ")
    username = read()
  end

  write("password: ")
  local password = read("*")

  local auth = context.runtime.services.get("auth")
  if not auth then
    print("auth service unavailable")
    return
  end

  local ok, result = auth.login(username, password)
  if not ok then
    print(("login failed: %s"):format(tostring(result)))
    return
  end

  print(("logged in as %s (clearance %s)"):format(result.username, tostring(result.clearance)))
end

return command
