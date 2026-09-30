local PROFILE = "workstation"
local MANIFEST = "manifest-workstation.lua"
local DEFAULT_ROLE = "workstation"
local DEFAULT_INSTALLER = "installer-workstation.lua"

local args = { ... }
local savedUpdate = {}
if fs.exists("/aeon/etc/update.cfg") then
  savedUpdate = dofile("/aeon/etc/update.cfg")
  if type(savedUpdate) ~= "table" then error("invalid update.cfg", 0) end
end
local sourceOptions = args[2] or savedUpdate
local REPO_OWNER = sourceOptions.owner or "Salweth"
local REPO_NAME = sourceOptions.repo or "cc-tweaked-A.E.O.N"
local DEFAULT_BRANCH = "main"

local function joinUrl(base, path)
  if string.sub(base, -1) == "/" then
    return base .. path
  end

  return base .. "/" .. path
end

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function fetch(url)
  local response = http.get(url, nil, true)
  if not response then
    return nil, ("request failed: %s"):format(url)
  end

  local body = response.readAll()
  response.close()
  return body
end

local function writeFile(path, content)
  ensureDir(path)

  local handle = fs.open(path, "w")
  if not handle then
    return false, ("cannot write file: %s"):format(path)
  end

  handle.write(content)
  handle.close()
  return true
end

local function loadTableFromString(source, chunkName)
  local fn, err = load(source, chunkName, "t", _ENV)
  if not fn then
    return nil, err
  end

  local ok, result = pcall(fn)
  if not ok then
    return nil, result
  end

  return result
end

local function writeManagedConfig(branch)
  local cfg = savedUpdate
  cfg.owner, cfg.repo, cfg.branch = REPO_OWNER, REPO_NAME, branch
  cfg.installer, cfg.profile = DEFAULT_INSTALLER, PROFILE
  local updateCfg = "return " .. textutils.serialize(cfg) .. "\n"

  local roleCfg = ([[return {
  role = %q
}
]]):format(DEFAULT_ROLE)

  local ok, err = writeFile("/aeon/etc/update.cfg", updateCfg)
  if not ok then
    error(err, 0)
  end

  if not fs.exists("/aeon/etc/role.cfg") then
    ok, err = writeFile("/aeon/etc/role.cfg", roleCfg)
    if not ok then
      error(err, 0)
    end
  end
end

local branch = args[1] or DEFAULT_BRANCH
local rawBase = ("https://raw.githubusercontent.com/%s/%s/%s"):format(REPO_OWNER, REPO_NAME, branch)

term.setTextColor(colors.orange)
print("A.E.O.N workstation installer")
term.setTextColor(colors.white)
print(("Source: %s/%s [%s]"):format(REPO_OWNER, REPO_NAME, branch))

local manifestBody, manifestErr = fetch(joinUrl(rawBase, MANIFEST))
if not manifestBody then
  error(manifestErr, 0)
end

local manifest, parseErr = loadTableFromString(manifestBody, "@" .. MANIFEST)
if type(manifest) ~= "table" or type(manifest.files) ~= "table" or #manifest.files == 0
  or manifest.profile ~= PROFILE then
  error(("invalid manifest: %s"):format(tostring(parseErr or "expected a non-empty manifest for " .. PROFILE)), 0)
end

for _, file in ipairs(manifest.files or {}) do
  local shouldWrite = true

  if file.mode == "keep" and fs.exists(file.path) then
    shouldWrite = false
    print(("keep    %s"):format(file.path))
  end

  if shouldWrite then
    local url = joinUrl(rawBase, file.source)
    local body, err = fetch(url)
    if not body then
      error(("download failed for %s: %s"):format(file.path, tostring(err)), 0)
    end

    local ok, writeErr = writeFile(file.path, body)
    if not ok then
      error(writeErr, 0)
    end

    print(("install %s"):format(file.path))
  end
end

writeManagedConfig(branch)

print(("AEON %s (%s) installed"):format(tostring(manifest.version or "unknown"), PROFILE))
print("Run `reboot` if startup does not launch immediately.")
