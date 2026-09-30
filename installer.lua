-- Standalone Pastebin bootstrap. The full installers stay on GitHub.
local profile, branch = ...
if not profile then
  write("Profile [workstation/server] (workstation): ")
  profile = read()
  if profile == "" then profile = "workstation" end
end
if profile ~= "workstation" and profile ~= "server" then
  error("usage: installer [workstation|server] [branch]", 0)
end
if not http then error("http api unavailable", 0) end
branch = branch or "main"
local path = "installer-" .. profile .. ".lua"
local url = ("https://raw.githubusercontent.com/Salweth/cc-tweaked-A.E.O.N/%s/%s"):format(branch, path)
local response, err = http.get(url, nil, true)
if not response then error(err or "failed to fetch installer", 0) end
local source = response.readAll()
response.close()
local run, loadErr = load(source, "@" .. path, "t", _ENV)
if not run then error(loadErr, 0) end
return run(branch)
