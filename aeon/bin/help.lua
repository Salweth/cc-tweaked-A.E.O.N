local command = {}

function command.run(_context, _args)
  local function has(name)
    return fs.exists(("/aeon/bin/%s.lua"):format(name))
  end

  print("Available commands:")
  print("  help      Show this help message")
  print("  clear     Clear the terminal")
  print("  ls        List files in a directory")
  print("  cat       Print a file")
  print("  edit      Edit a file with the CraftOS editor")
  print("  ps        List kernel tasks")
  print("  devices   List detected peripherals")
  print("  svc       List system services")
  print("  login     Open an auth session")
  print("  logout    Close the current auth session")
  print("  auth      Show auth status or active sessions")
  if has("app") then
    print("  app       Manage installed optional packages")
  end
  print("  whoami    Show current identity")
  if has("package") then
    print("  package   Server-side package distribution")
  end
  print("  net       Show AEON network status")
  print("  node      Discover and inspect AEON nodes")
  print("  send      Send a raw AEON request")
  print("  update    Update AEON from the remote repository")
  print("  ping      Send a test AEON network message")
  print("  role      Show machine role")
  print("  hostname  Show terminal hostname")
  print("  reboot    Reboot the computer")
end

return command
