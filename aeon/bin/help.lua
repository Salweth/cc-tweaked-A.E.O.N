local command = {}

function command.run(_context, _args)
  print("Available commands:")
  print("  help      Show this help message")
  print("  clear     Clear the terminal")
  print("  ls        List files in a directory")
  print("  cat       Print a file")
  print("  ps        List kernel tasks")
  print("  devices   List detected peripherals")
  print("  svc       List system services")
  print("  login     Open an auth session")
  print("  whoami    Show current identity")
  print("  update    Update AEON from the remote repository")
  print("  ping      Send a test AEON network message")
  print("  role      Show machine role")
  print("  hostname  Show terminal hostname")
  print("  reboot    Reboot the computer")
end

return command
