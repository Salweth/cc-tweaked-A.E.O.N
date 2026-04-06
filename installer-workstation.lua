local PROFILE = "workstation"
local MANIFEST = "manifest-workstation.lua"
local DEFAULT_ROLE = "workstation"
local DEFAULT_INSTALLER = "installer-workstation.lua"

local REPO_OWNER = "Salweth"
local REPO_NAME = "cc-tweaked-A.E.O.N"
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
  local updateCfg = ([[return {
  owner = %q,
  repo = %q,
  branch = %q,
  installer = %q,
  profile = %q,
}
]]):format(REPO_OWNER, REPO_NAME, branch, DEFAULT_INSTALLER, PROFILE)

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

local args = { ... }
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
if not manifest then
  error(("invalid manifest: %s"):format(tostring(parseErr)), 0)
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
