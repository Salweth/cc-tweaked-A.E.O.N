local packageCore = {}

local DB_PATH = "/aeon/var/packages.db"
local SERVER_REPO = "/aeon/packages"
local DISK_PACKAGE_ROOT = "aeon-package"
local ALLOWED_PREFIXES = {
  "/aeon/apps/",
  "/aeon/bin/",
  "/aeon/services/",
  "/aeon/etc/",
  "/aeon/lib/",
}

local function nowUtc()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function readTable(path, fallback)
  if not fs.exists(path) or fs.isDir(path) then
    return fallback
  end

  local ok, result = pcall(dofile, path)
  if not ok or type(result) ~= "table" then
    return fallback
  end

  return result
end

local function writeTable(path, value)
  ensureDir(path)
  local handle = fs.open(path, "w")
  if not handle then
    return false, ("unable to write %s"):format(path)
  end

  handle.write("return ")
  handle.write(textutils.serialize(value, { compact = false }))
  handle.write("\n")
  handle.close()
  return true
end

local function startsWith(value, prefix)
  return string.sub(value, 1, #prefix) == prefix
end

local function isAllowedTarget(path)
  for _, prefix in ipairs(ALLOWED_PREFIXES) do
    if startsWith(path, prefix) then
      return true
    end
  end

  return false
end

local function normalizeMount(input)
  local mount = input or "/disk"
  if mount == "disk" then
    return "/disk"
  end
  if string.sub(mount, 1, 1) ~= "/" then
    return "/" .. mount
  end
  return mount
end

local function loadManifest(packageRoot)
  local manifestPath = fs.combine(packageRoot, "manifest.lua")
  if not fs.exists(manifestPath) then
    return nil, ("manifest not found in %s"):format(packageRoot)
  end

  local ok, manifest = pcall(dofile, manifestPath)
  if not ok then
    return nil, manifest
  end

  if type(manifest) ~= "table" then
    return nil, "manifest must return a table"
  end

  return manifest
end

local function validateManifest(manifest, role)
  if type(manifest.id) ~= "string" or manifest.id == "" then
    return false, "manifest.id is required"
  end

  if type(manifest.version) ~= "string" or manifest.version == "" then
    return false, "manifest.version is required"
  end

  if type(manifest.files) ~= "table" or #manifest.files == 0 then
    return false, "manifest.files must contain at least one file"
  end

  if manifest.target and manifest.target.roles and role then
    local allowed = false
    for _, allowedRole in ipairs(manifest.target.roles) do
      if allowedRole == role then
        allowed = true
        break
      end
    end

    if not allowed then
      return false, ("package %s does not target role %s"):format(manifest.id, role)
    end
  end

  for _, entry in ipairs(manifest.files) do
    if type(entry.from) ~= "string" or entry.from == "" then
      return false, "manifest file entry missing from"
    end

    if type(entry.to) ~= "string" or entry.to == "" then
      return false, "manifest file entry missing to"
    end

    if not isAllowedTarget(entry.to) then
      return false, ("target not allowed: %s"):format(entry.to)
    end
  end

  return true
end

local function copyFile(source, target)
  local readHandle = fs.open(source, "r")
  if not readHandle then
    return false, ("unable to open source: %s"):format(source)
  end

  local content = readHandle.readAll()
  readHandle.close()

  ensureDir(target)
  local writeHandle = fs.open(target, "w")
  if not writeHandle then
    return false, ("unable to open target: %s"):format(target)
  end

  writeHandle.write(content)
  writeHandle.close()
  return true
end

local function copyTree(sourceRoot, targetRoot)
  if not fs.exists(sourceRoot) then
    return false, ("source path not found: %s"):format(sourceRoot)
  end

  if fs.isDir(sourceRoot) then
    if not fs.exists(targetRoot) then
      fs.makeDir(targetRoot)
    end

    for _, name in ipairs(fs.list(sourceRoot)) do
      local ok, err = copyTree(fs.combine(sourceRoot, name), fs.combine(targetRoot, name))
      if not ok then
        return false, err
      end
    end

    return true
  end

  return copyFile(sourceRoot, targetRoot)
end

local function cleanupParentDirs(path)
  local parent = fs.getDir(path)
  while parent and parent ~= "" and parent ~= "/" do
    if not fs.exists(parent) or not fs.isDir(parent) then
      break
    end

    local items = fs.list(parent)
    if #items > 0 then
      break
    end

    fs.delete(parent)
    parent = fs.getDir(parent)
  end
end

local function runHook(path, context)
  if not fs.exists(path) or fs.isDir(path) then
    return true
  end

  local ok, result = pcall(dofile, path)
  if not ok then
    return false, result
  end

  if type(result) == "function" then
    local hookOk, hookErr = pcall(result, context)
    if not hookOk then
      return false, hookErr
    end
  end

  return true
end

local function findDriveForMount(mountPath)
  local normalized = normalizeMount(mountPath)

  if not disk or type(disk.getMountPath) ~= "function" then
    return nil
  end

  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "drive" and disk.isPresent(name) and disk.hasData(name) then
      local driveMount = disk.getMountPath(name)
      if driveMount and ("/" .. driveMount) == normalized then
        return name
      end
    end
  end

  return nil
end

local function makeDiskLabel(manifest)
  local name = manifest.name or manifest.id or "Package"
  return ("Floppy Disk - %s v%s"):format(name, tostring(manifest.version or "unknown"))
end

function packageCore.loadDb()
  local db = readTable(DB_PATH, { installed = {} })
  db.installed = db.installed or {}
  return db
end

function packageCore.saveDb(db)
  return writeTable(DB_PATH, db)
end

function packageCore.listInstalled()
  local db = packageCore.loadDb()
  local items = {}

  for id, entry in pairs(db.installed) do
    entry.id = id
    table.insert(items, entry)
  end

  table.sort(items, function(a, b)
    return a.id < b.id
  end)

  return items
end

function packageCore.getInstalled(id)
  local db = packageCore.loadDb()
  local entry = db.installed[id]
  if not entry then
    return nil
  end

  entry.id = id
  return entry
end

function packageCore.listAvailable()
  local items = {}
  if not fs.exists(SERVER_REPO) or not fs.isDir(SERVER_REPO) then
    return items
  end

  for _, name in ipairs(fs.list(SERVER_REPO)) do
    local packageRoot = fs.combine(SERVER_REPO, name)
    if fs.isDir(packageRoot) then
      local manifest = loadManifest(packageRoot)
      if manifest then
        table.insert(items, {
          id = manifest.id,
          name = manifest.name or manifest.id,
          version = manifest.version,
          issuer = manifest.issuer or "unknown",
          root = packageRoot,
        })
      end
    end
  end

  table.sort(items, function(a, b)
    return a.id < b.id
  end)
  return items
end

function packageCore.inspectDisk(mountPath)
  local mount = normalizeMount(mountPath)
  local packageRoot = fs.combine(mount, DISK_PACKAGE_ROOT)
  local manifest, err = loadManifest(packageRoot)
  if not manifest then
    return false, err
  end

  return true, {
    mount = mount,
    root = packageRoot,
    manifest = manifest,
  }
end

function packageCore.writeToDisk(packageId, mountPath)
  local mount = normalizeMount(mountPath)
  if not fs.exists(mount) or not fs.isDir(mount) then
    return false, ("disk mount not found: %s"):format(mount)
  end

  local packageRoot = fs.combine(SERVER_REPO, packageId)
  local manifest, err = loadManifest(packageRoot)
  if not manifest then
    return false, err
  end

  local targetRoot = fs.combine(mount, DISK_PACKAGE_ROOT)
  if fs.exists(targetRoot) then
    fs.delete(targetRoot)
  end

  local ok, copyErr = copyTree(packageRoot, targetRoot)
  if not ok then
    return false, copyErr
  end

  local driveName = findDriveForMount(mount)
  if driveName and disk and type(disk.setLabel) == "function" then
    local labelOk, labelErr = pcall(disk.setLabel, driveName, makeDiskLabel(manifest))
    if not labelOk then
      return false, labelErr
    end
  end

  return true, manifest
end

function packageCore.installFromDisk(role, mountPath)
  local ok, inspected = packageCore.inspectDisk(mountPath)
  if not ok then
    return false, inspected
  end

  local manifest = inspected.manifest
  local valid, err = validateManifest(manifest, role)
  if not valid then
    return false, err
  end

  local copiedFiles = {}
  for _, entry in ipairs(manifest.files) do
    local source = fs.combine(inspected.root, entry.from)
    if not fs.exists(source) or fs.isDir(source) then
      return false, ("package file missing: %s"):format(entry.from)
    end

    local copyOk, copyErr = copyFile(source, entry.to)
    if not copyOk then
      return false, copyErr
    end

    table.insert(copiedFiles, entry.to)
  end

  local hookOk, hookErr = runHook(fs.combine(inspected.root, "install.lua"), {
    role = role,
    mount = inspected.mount,
    manifest = manifest,
  })
  if not hookOk then
    return false, hookErr
  end

  local db = packageCore.loadDb()
  db.installed[manifest.id] = {
    name = manifest.name or manifest.id,
    version = manifest.version,
    description = manifest.description,
    issuer = manifest.issuer or "unknown",
    signature = manifest.signature,
    permissions = manifest.permissions or {},
    entrypoints = manifest.entrypoints or {},
    files = copiedFiles,
    installed_at = nowUtc(),
  }

  local saveOk, saveErr = packageCore.saveDb(db)
  if not saveOk then
    return false, saveErr
  end

  return true, db.installed[manifest.id]
end

function packageCore.removeInstalled(id)
  local db = packageCore.loadDb()
  local entry = db.installed[id]
  if not entry then
    return false, ("package not installed: %s"):format(id)
  end

  local files = entry.files or {}
  table.sort(files, function(a, b)
    return #a > #b
  end)

  for _, path in ipairs(files) do
    if fs.exists(path) then
      fs.delete(path)
      cleanupParentDirs(path)
    end
  end

  db.installed[id] = nil
  local ok, err = packageCore.saveDb(db)
  if not ok then
    return false, err
  end

  return true
end

return packageCore
