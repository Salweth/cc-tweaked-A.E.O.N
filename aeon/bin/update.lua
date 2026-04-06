local command = {}

function command.run(_context, args)
  local branch = args[1]

  if not http then
    print("http api unavailable")
    return
  end

  local cfg = {}
  if fs.exists("/aeon/etc/update.cfg") then
    cfg = dofile("/aeon/etc/update.cfg")
  end

  local roleName = "workstation"
  if fs.exists("/aeon/etc/role.cfg") then
    local roleCfg = dofile("/aeon/etc/role.cfg")
    roleName = roleCfg.role or roleName
  end

  local owner = cfg.owner or "Salweth"
  local repo = cfg.repo or "cc-tweaked-A.E.O.N"
  local selectedBranch = branch or cfg.branch or "main"
  local installer = cfg.installer
  if not installer or installer == "" then
    if roleName == "server" then
      installer = "installer-server.lua"
    else
      installer = "installer-workstation.lua"
    end
  end
  local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(owner, repo, selectedBranch, installer)

  print(("update source: %s/%s [%s] via %s"):format(owner, repo, selectedBranch, installer))

  local response = http.get(url, nil, true)
  if not response then
    print("failed to fetch installer")
    return
  end

  local source = response.readAll()
  response.close()

  local fn, err = load(source, "@" .. installer, "t", _ENV)
  if not fn then
    print(("invalid installer: %s"):format(tostring(err)))
    return
  end

  local ok, runErr = pcall(fn, selectedBranch)
  if not ok then
    print(("update failed: %s"):format(tostring(runErr)))
    return
  end

  print("update complete")
end

return command
