-- Run from the repository root with Lua 5.2+ (no Minecraft world required).
local function readSource(path)
  local file = assert(io.open(path:gsub("^/", ""), "r"))
  local source = file:read("*a")
  file:close()
  return source
end

local function serialize(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local fields = {}
  for key, item in pairs(value) do
    fields[#fields + 1] = "[" .. serialize(key) .. "]=" .. serialize(item)
  end
  return "{" .. table.concat(fields, ",") .. "}"
end

local terminalFixture = dofile("tests/terminal.lua")

local function fixture(width, height, color)
  local env = setmetatable({}, { __index = _G })
  local files, hardware, queue, output, requests, modules = {}, {}, {}, {}, {}, {}
  local dirs = { ["/"] = true }
  local function normalize(path) return "/" .. path:gsub("^/", "") end
  local function execute(path, ...)
    local source = files[normalize(path)]
    if not source and not env.installedOnly then source = readSource(path) end
    assert(source, "missing installed dependency: " .. path)
    local result = assert(load(source, "@" .. path, "t", env))(...)
    modules[path] = result
    return result
  end
  env.dofile = execute
  env.print = function(...) output[#output + 1] = table.concat({...}, " ") end
  env.write = function() end
  env.read = function() return coroutine.yield("test:input") end
  local screen, surfaces = terminalFixture(env, output, width, height, color)
  env.textutils = { serialize = serialize, formatTime = function() return "12:00" end }
  env.os = {
    epoch = function() return 1000 end, clock = function() return 1 end,
    day = function() return 1 end, time = function() return 12 end,
    getComputerID = function() return 1 end, getComputerLabel = function() return "test" end,
    startTimer = function() return 1 end,
    queueEvent = function(...) queue[#queue + 1] = {...} end,
    pullEventRaw = function()
      if #queue > 0 then return table.unpack(table.remove(queue, 1)) end
      modules["/aeon/core/kernel.lua"].stop()
      return "test:done"
    end,
  }
  env.os.pullEvent = function(filter)
    local event = table.pack(coroutine.yield(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
  end
  env.fs = {
    combine = function(a, b) return normalize((a .. "/" .. b):gsub("/+", "/")) end,
    exists = function(path) return files[normalize(path)] ~= nil or dirs[normalize(path)] == true end,
    isDir = function(path) return dirs[normalize(path)] == true end,
    getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
    makeDir = function(path) dirs[normalize(path)] = true end,
    open = function(path, mode)
      path = normalize(path)
      if mode == "r" then
        if not files[path] then return nil end
        return { readAll = function() return files[path] end, close = function() end }
      end
      if env.failWrite == path then return nil end
      if mode ~= "a" then files[path] = "" end
      return {
        write = function(value) files[path] = (files[path] or "") .. value end,
        writeLine = function(value) files[path] = (files[path] or "") .. value .. "\n" end,
        close = function() end,
      }
    end,
  }
  env.http = { get = function(url)
    requests[#requests + 1] = url
    if env.failFetch and url:find(env.failFetch, 1, true) then return nil, "offline" end
    local path = url:match("/([^/]+%.lua)$")
    local aeonPath = url:match("/(aeon/.*)$")
    path = aeonPath or path
    local source = env.httpBody or readSource(assert(path, url))
    return { readAll = function() return source end, close = function() end }
  end }
  env.peripheral = {
    getNames = function()
      local names = {}
      for name in pairs(hardware) do names[#names + 1] = name end
      table.sort(names)
      return names
    end,
    getType = function(name) return table.unpack(hardware[name].types) end,
    wrap = function(name)
      if hardware[name].broken then error("disconnected during scan") end
      return hardware[name].object
    end,
    getMethods = function(name)
      local methods = {}
      for method in pairs(hardware[name].object) do methods[#methods + 1] = method end
      return methods
    end,
  }
  return { env = env, files = files, hardware = hardware, queue = queue,
    output = output, requests = requests, modules = modules, execute = execute,
    screen = screen, surfaces = surfaces }
end

local function modem(wireless, fail)
  local channels, sent = {}, {}
  return { types = { "modem" }, channels = channels, sent = sent, object = {
    open = function(channel) if fail then error("broken modem") end; channels[channel] = true end,
    close = function(channel) channels[channel] = nil end,
    isOpen = function(channel) return channels[channel] == true end,
    isWireless = function() return wireless end,
    transmit = function(...) sent[#sent + 1] = {...} end,
  } }
end

local tests = {}

function tests.capabilities()
  local f = fixture()
  f.hardware.left = modem(true)
  f.hardware.screen = { types = { "custom", "monitor" }, object = {
    write = function() return nil, "tail" end, clear = function() end,
    setCursorPos = function() end, getSize = function() return 20, 10 end,
  } }
  f.hardware.sound = { types = { "speaker" }, object = {
    playNote = function() return false end, playSound = function() end,
    playAudio = function() error("audio failed") end, stop = function() end,
  } }
  f.hardware.unknown = { types = { "unknown" }, object = {} }
  f.hardware.vanishing = { types = { "monitor" }, broken = true }
  local registry = f.execute("/aeon/core/registry.lua")
  registry.scan()
  assert(#registry.list() == 4 and registry.find("modem").name == "left")
  assert(#registry.findAll("modem") == 1 and registry.get("unknown"))
  local layer = f.execute("/aeon/core/devices.lua").create(registry, { queueEvent = f.env.os.queueEvent })
  assert(layer.findCapability("rfid_reader") == nil)
  assert(#layer.findAllCapabilities("missing") == 0)
  assert(layer.findCapability("monitor").name == "screen")
  assert(layer.findCapability("display").driver == "cc.monitor")
  local ok, width, height = layer.findCapability("display").call("getSize")
  assert(ok and width == 20 and height == 10)
  local callOk, value, tail = layer.findCapability("display").call("write", "hi")
  assert(callOk and value == nil and tail == "tail")
  local speaker = layer.findCapability("speaker")
  local success, accepted = speaker.call("playNote", "harp")
  assert(success and accepted == false)
  assert(not speaker.call("playAudio"))
  assert(not speaker.call("inventedMethod"))
  assert(layer.registerDriver({ id = "broken", match = function() error("bad match") end,
    bindCapabilities = function() return {} end }))
  assert(layer.registerDriver({ id = "bad-bind", match = function() return true end,
    bindCapabilities = function() error("bad bind") end }))
  assert(layer.registerDriver({ id = "invalid", match = function() return true end,
    bindCapabilities = function() return { bogus = false } end }))
  assert(not layer.registerDriver({ id = "invalid" }))
  assert(layer.registerDriver({ id = "method-based", match = function(entry, helpers)
    return helpers.hasMethods(entry, { "getSize" }) end,
    bindCapabilities = function(entry) return { test_size = { size = entry.object.getSize } } end }))
  registry.refresh()
  assert(layer.findCapability("modem") and layer.findCapability("test_size"))
  assert(not layer.findCapability("bogus"))
  assert(not speaker.call("stop")) -- Every refresh expires old handles.
  local old = layer.findCapability("modem")
  f.hardware.left = nil
  registry.refresh("detach", "left")
  assert(not layer.findCapability("modem") and not old.call("open", 42))
  f.hardware.left = modem(false)
  registry.refresh("attach", "left")
  assert(layer.findCapability("modem").call("open", 42))
  assert(not old.call("open", 42)) -- Same name must not revive the old handle.
  assert(#f.queue > 0)
  local isolated = f.execute("/aeon/core/devices.lua").create(registry, { drivers = { "missing.lua" } })
  assert(not isolated.findCapability("modem"))
end

function tests.hotplug_network()
  local f = fixture()
  local registry = f.execute("/aeon/core/registry.lua")
  registry.scan()
  local layer = f.execute("/aeon/core/devices.lua").create(registry, { queueEvent = f.env.os.queueEvent })
  local kernel = f.execute("/aeon/core/kernel.lua")
  local log = { info = function() end, warn = function() end, error = error, debug = function() end }
  local runtime = { config = {}, role = {}, hostname = "test", logger = log }
  kernel.init(runtime)
  local context = { devices = layer, registry = registry, kernel = kernel, runtime = runtime,
    config = {}, role = {}, log = log, on = kernel.on, emit = kernel.emit }
  f.execute("/aeon/services/svc_registry.lua").start(context)
  local net = f.execute("/aeon/services/svc_net.lua").start(context)
  assert(not net.send("test", {}))
  local function drain()
    while #f.queue > 0 do kernel.dispatch(table.remove(f.queue, 1)) end
  end
  f.hardware.left = modem(false)
  kernel.dispatch({ "peripheral", "left" }); drain()
  assert(net.modem.name == "left" and not net.isWireless and net.send("test", {}))
  f.hardware.right = modem(true)
  kernel.dispatch({ "peripheral", "right" }); drain()
  assert(net.modem.name == "right" and net.isWireless)
  assert(f.hardware.right.channels[42] and f.hardware.right.channels[1001])
  f.hardware.right = nil
  kernel.dispatch({ "peripheral_detach", "right" }); drain()
  assert(net.modem.name == "left" and not net.isWireless)
  f.hardware.left = nil
  kernel.dispatch({ "peripheral_detach", "left" }); drain()
  assert(net.modem == nil and not net.send("test", {}))
  f.hardware.broken = modem(true, true)
  f.hardware.left = modem(false)
  kernel.dispatch({ "peripheral", "left" }); drain()
  assert(net.modem.name == "left" and net.send("test", {}))
  for _, task in ipairs(kernel.listTasks()) do assert(task.status ~= "error") end
end

local function install(profile, width, height, color)
  local f = fixture(width, height, color)
  f.execute("installer.lua", profile, "test-branch")
  local cfg = f.execute("/aeon/etc/update.cfg")
  assert(cfg.profile == profile and cfg.branch == "test-branch")
  assert(cfg.installer == "installer-" .. profile .. ".lua")
  assert(f.execute("/aeon/etc/role.cfg").role == profile)
  assert(f.files["/aeon/core/devices.lua"] and f.files["/aeon/drivers/speaker.lua"])
  return f
end

function tests.install_update_boot()
  for _, profile in ipairs({ "workstation", "server" }) do
    local f = install(profile)
    local persistent = {
      ["/aeon/etc/aeon.cfg"] = 'return { hostname = "local", theme = "amber" }',
      ["/aeon/etc/users.cfg"] = 'return { users = {} }',
      ["/aeon/etc/network.cfg"] = 'return { node_channel = 1234 }',
      ["/aeon/etc/role.cfg"] = 'return { role = "' .. profile .. '", custom = true }',
      ["/aeon/var/log/system.log"] = "old log\n",
      ["/aeon/home/note"] = "user data",
      ["/aeon/var/packages.db"] = "return { installed = {} }",
      ["/aeon/etc/currency.cfg"] = "return { custom = true }",
      ["/aeon/packages/currency-management/etc/currency.cfg"] = "return { custom = true }",
    }
    for path, content in pairs(persistent) do f.files[path] = content end
    f.files["/aeon/etc/update.cfg"] = 'return { owner="custom-owner", repo="custom-repo", branch="old", profile="'
      .. profile .. '", installer="installer.lua", custom=true }'
    f.execute("/aeon/bin/update.lua").run({}, { "feature/new" })
    for path, content in pairs(persistent) do assert(f.files[path] == content, "overwritten: " .. path) end
    local cfg = f.execute("/aeon/etc/update.cfg")
    assert(cfg.custom and cfg.owner == "custom-owner" and cfg.repo == "custom-repo")
    assert(cfg.branch == "feature/new" and cfg.profile == profile)
    assert(f.output[#f.output] == "update complete")
    for _, url in ipairs(f.requests) do
      assert(not url:find("/main/", 1, true), "branch lost: " .. url)
    end
    assert(f.requests[#f.requests]:find("/custom-owner/custom-repo/feature/new/", 1, true))
    -- Boot exclusively from the installed filesystem: missing manifest files fail here.
    f.env.installedOnly = true
    f.execute("/startup.lua")
    local runtime = f.modules["/aeon/core/kernel.lua"].runtime
    assert(runtime.devices and runtime.role.role == profile)
    assert(runtime.ui.theme.accent == f.env.colors.cyan)
    for _, service in ipairs(runtime.services.list()) do
      assert(service.status == "running", service.name .. " failed on " .. profile)
    end
    for _, task in ipairs(runtime.kernel.listTasks()) do assert(task.status ~= "error", task.name) end
  end
end

function tests.install_errors()
  local f = fixture()
  assert(not pcall(f.execute, "installer.lua", "invalid"))
  f.env.failFetch = "installer-server.lua"
  assert(not pcall(f.execute, "installer.lua", "server"))
  f.env.failFetch = nil
  f.env.httpBody = "invalid lua !"
  assert(not pcall(f.execute, "installer.lua", "server"))
  f.env.httpBody = "return {}"
  assert(not pcall(f.execute, "installer-server.lua"))
  f.env.httpBody = readSource("manifest-workstation.lua")
  assert(not pcall(f.execute, "installer-server.lua"))
  f.env.httpBody = nil
  f.env.failWrite = "/aeon/core/devices.lua"
  assert(not pcall(f.execute, "installer-server.lua"))
  assert(not f.files["/aeon/etc/update.cfg"])
  for _, profile in ipairs({ "workstation", "server" }) do
    f = install(profile)
    local cfg = f.files["/aeon/etc/update.cfg"]
    f.env.failFetch = "aeon/core/devices.lua"
    f.execute("/aeon/bin/update.lua").run({}, { "broken-branch" })
    assert(f.files["/aeon/etc/update.cfg"] == cfg)
    assert(f.output[#f.output]:find("update failed", 1, true))
  end
end

function tests.legacy_update_and_prompt()
  local f = fixture()
  f.env.read = function() return "" end
  f.execute("installer.lua")
  assert(f.execute("/aeon/etc/update.cfg").profile == "workstation")
  f = fixture()
  f.env.read = function() return "server" end
  f.execute("installer.lua")
  assert(f.execute("/aeon/etc/update.cfg").profile == "server")
  for _, profile in ipairs({ "workstation", "server" }) do
    f = install(profile)
    f.files["/aeon/etc/update.cfg"] = 'return { owner="legacy-owner", repo="legacy-repo", branch="stable" }'
    f.execute("/aeon/bin/update.lua").run({}, {})
    local cfg = f.execute("/aeon/etc/update.cfg")
    assert(cfg.profile == profile and cfg.branch == "stable")
    assert(cfg.owner == "legacy-owner" and cfg.repo == "legacy-repo")
    -- Older update commands pass just the branch; installers must retain the source.
    f.execute("installer-" .. profile .. ".lua", "old-client")
    assert(f.requests[#f.requests]:find("/legacy-owner/legacy-repo/old-client/", 1, true))
    f.files["/aeon/etc/update.cfg"] = nil
    f.execute("/aeon/bin/update.lua").run({}, {})
    assert(f.execute("/aeon/etc/update.cfg").profile == profile)
  end
  f = fixture()
  f.files["/aeon/etc/update.cfg"] = "return false"
  assert(not pcall(f.execute, "installer-server.lua"))
  assert(#f.requests == 0) -- Reject broken configuration before replacing files.
end

function tests.manifests()
  for _, name in ipairs({ "manifest.lua", "manifest-workstation.lua", "manifest-server.lua" }) do
    local manifest = assert(load(readSource(name)))()
    local paths = {}
    for _, entry in ipairs(manifest.files) do
      assert(not paths[entry.path], "duplicate: " .. entry.path)
      paths[entry.path] = true
      assert(#readSource(entry.source) > 0)
      if entry.path:find("/etc/", 1, true) then assert(entry.mode == "keep") end
    end
    assert(paths["/aeon/core/devices.lua"] and paths["/aeon/drivers/speaker.lua"])
  end
end

dofile("tests/ui.lua")(tests, fixture, install)

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  tests[name]()
  print("PASS " .. name)
end
print(("%d suites passed"):format(#names))
