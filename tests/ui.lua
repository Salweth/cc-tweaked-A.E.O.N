return function(tests, fixture, install)
  local function boot(f)
    f.env.installedOnly = true
    f.execute("/startup.lua")
    return f.modules["/aeon/core/kernel.lua"].runtime
  end
  local function drain(f, runtime)
    local steps = 0
    while #f.queue > 0 do
      steps = steps + 1
      assert(steps < 200, "event loop did not settle")
      runtime.kernel.dispatch(table.remove(f.queue, 1))
    end
  end
  local function send(f, runtime, ...)
    runtime.kernel.dispatch({ ... })
    drain(f, runtime)
  end
  local function line(f, runtime, text)
    send(f, runtime, "paste", text)
    send(f, runtime, "key", f.env.keys.enter)
  end
  local function picture(screen)
    local rows = {}
    for _, row in ipairs(screen.lines) do rows[#rows + 1] = row.text end
    return table.concat(rows, "\n")
  end
  local function preview(name, f)
    if AEON_PREVIEW then AEON_PREVIEW(name, f.screen) end
  end

  function tests.ui_components_and_input()
    for _, color in ipairs({ true, false }) do
      local f = fixture(26, 10, color)
      local display = f.execute("/aeon/drivers/display.lua")
      local module = f.execute("/aeon/core/ui.lua")
      local view = module.create(display.create(f.screen, { input = true }), "amber")
      assert(view.theme.name == "aeon")
      assert(view.theme.accent == (color and f.env.colors.cyan or f.env.colors.white))
      view.clear()
      view.header("FIELD", "SITE-01 / NODE-07")
      view.status(4, "NETWORK", "ONLINE")
      view.status(5, "AUTH", "RESTRICTED")
      view.status(6, "POWER", "WARNING")
      view.status(7, "ALERT", "CRITICAL")
      assert(picture(f.screen):find("ONLINE", 1, true))
      assert(f.screen.lines[4].fg[11] == view.theme.success)
      view.at(26, 10, "overflow text")
      assert(f.screen.lines[10].text:sub(26, 26) == "o")
      view.at(27, 11, "outside")
      assert(module.truncate("abcdefgh", 5) == "ab...")
      assert(module.truncate("abc", 0) == "")
      local monitor = module.create(display.create(f.screen), "aeon")
      local value, err = monitor.read()
      assert(value == nil and err == "surface has no keyboard input")
      view.cursor(1, 9)
      local input, routine
      routine = coroutine.create(function() input = view.read({ prompt = "Password: ", mask = "*" }) end)
      assert(coroutine.resume(routine))
      assert(coroutine.resume(routine, "paste", "secret"))
      assert(not picture(f.screen):find("secret", 1, true))
      assert(picture(f.screen):find("******", 1, true))
      assert(coroutine.resume(routine, "key", f.env.keys.left))
      assert(coroutine.resume(routine, "key", f.env.keys.backspace))
      assert(coroutine.resume(routine, "char", "X"))
      assert(coroutine.resume(routine, "key", f.env.keys.home))
      assert(coroutine.resume(routine, "key", f.env.keys.delete))
      assert(coroutine.resume(routine, "key", f.env.keys["end"]))
      assert(coroutine.resume(routine, "paste", "\nOK\r"))
      assert(coroutine.resume(routine, "key", f.env.keys.enter))
      assert(input == "ecrXtOK" and not f.screen.blink)
      f.hardware.monitor = { types = { "monitor" }, object = f.screen }
      local registry = f.execute("/aeon/core/registry.lua")
      registry.scan()
      local layer = f.execute("/aeon/core/devices.lua").create(registry)
      local adapted = module.create(display.fromCapability(function()
        return layer.findCapability("display")
      end), "aeon")
      adapted.at(1, 8, "CAPABILITY DISPLAY")
      registry.refresh()
      adapted.at(1, 8, "REFRESHED DISPLAY")
      assert(picture(f.screen):find("REFRESHED DISPLAY", 1, true))
      f.hardware.monitor = nil
      registry.refresh()
      assert(not pcall(adapted.clear))
    end
  end

  function tests.shell_apps_and_shared_auth()
    local f = install("workstation")
    local runtime = boot(f)
    local rootId = runtime.kernel.foreground["local"]
    line(f, runtime, "login agent")
    line(f, runtime, "change-me")
    assert(runtime.services.get("auth").current(rootId).username == "agent")
    assert(picture(f.screen):find("agent C-2", 1, true))
    line(f, runtime, "clear")
    preview("terminal-51x19", f)
    local header = f.screen.lines[1].text
    f.files["/aeon/bin/flood.lua"] = [[return { run = function(context)
      for i = 1, 40 do print("legacy command output " .. i) end
    end }]]
    line(f, runtime, "flood")
    assert(f.screen.lines[1].text == header) -- Legacy output cannot scroll the header.
    local backgroundIdentity = false
    runtime.kernel.spawn("svc:test", function()
      backgroundIdentity = runtime.services.get("auth").current()
    end, { kind = "service" })
    assert(backgroundIdentity == nil)
    drain(f, runtime)
    f.env.observed = {}
    f.files["/aeon/apps/probe.lua"] = [[return {
      name = "probe",
      run = function(runtime)
        local task = runtime.kernel.getCurrentTask()
        observed.id = task.id
        observed.parent = task.parent
        observed.scope = task.auth_scope
        observed.user = runtime.services.get("auth").current().username
        observed.role = runtime.services.get("auth").hasRole("field")
        observed.clearance = runtime.services.get("auth").hasClearance(2)
        runtime.ui.setEventHandler(function()
          observed.hookHits = (observed.hookHits or 0) + 1
        end)
        runtime.apps.run({ name = "other-surface", run = function(other)
          observed.otherUser = other.services.get("auth").current()
        end }, { surface = "separate" })
        runtime.ui.clear()
        runtime.ui.header("PROBE", observed.user)
        while true do
          local event = runtime.ui.wait()
          if event == "key" then observed.launchKey = true end
          if event == "char" then observed.event = event; break end
        end
      end,
      stop = function() observed.stops = (observed.stops or 0) + 1 end,
    }]]
    line(f, runtime, "probe")
    local probe = f.env.observed
    assert(probe.id ~= rootId and probe.parent == rootId and probe.scope == rootId)
    assert(probe.user == "agent" and probe.role and probe.clearance)
    assert(probe.otherUser == nil)
    assert(probe.event == nil and not probe.launchKey, "launching Enter leaked into new app")
    assert(not runtime.kernel.isForeground(rootId))
    assert(#runtime.services.get("auth").listSessions() == 1)
    send(f, runtime, "char", "q")
    assert(probe.event == "char" and probe.stops == 1)
    assert(runtime.kernel.isForeground(rootId))
    assert(runtime.kernel.getTask(rootId).status == "waiting")
    assert(runtime.services.get("auth").current(rootId).username == "agent")
    local hits = probe.hookHits
    f.files["/aeon/apps/waiter.lua"] = [[return { name="waiter", run=function(runtime)
      runtime.ui.wait("char")
    end }]]
    line(f, runtime, "waiter")
    send(f, runtime, "char", "q")
    assert(probe.hookHits == hits, "old app event hook leaked into another app")
    f.files["/aeon/apps/broken.lua"] = [[return {
      name = "broken", run = function() error("test failure") end,
      stop = function() observed.brokenStop = true end,
    }]]
    line(f, runtime, "broken")
    assert(probe.brokenStop and runtime.kernel.getTask(rootId).status == "waiting")
    assert(picture(f.screen):find("app failed", 1, true))
    f.files["/aeon/apps/bad-contract.lua"] = [[return {
      name = false, run = function() end, stop = "invalid",
    }]]
    line(f, runtime, "bad-contract")
    assert(runtime.kernel.getTask(rootId).status == "waiting")
    f.files["/aeon/apps/logout-app.lua"] = [[return { name="logout-app", run=function(runtime)
      runtime.services.get("auth").logout()
    end }]]
    line(f, runtime, "logout-app")
    assert(runtime.services.get("auth").current(rootId) == nil)
    assert(#runtime.services.get("auth").listSessions() == 0)
    line(f, runtime, "login agent"); line(f, runtime, "change-me")
    line(f, runtime, "probe")
    send(f, runtime, "terminate")
    assert(runtime.kernel.getTask(rootId).status == "waiting")
    assert(runtime.services.get("auth").current(rootId).username == "agent")
    send(f, runtime, "terminate") -- Closing the owning surface clears its session.
    assert(runtime.services.get("auth").current(rootId) == nil)
  end

  function tests.server_shell_return_and_resize()
    for _, dimensions in ipairs({ {51,19}, {26,20}, {18,8}, {7,3}, {1,1} }) do
      local f = install("server", dimensions[1], dimensions[2])
      local runtime = boot(f)
      local coreId = runtime.kernel.foreground["local"]
      assert(runtime.kernel.getTask(coreId).status == "waiting")
      assert(picture(f.screen):find("A", 1, true))
      if dimensions[1] >= 26 then
        assert(picture(f.screen):find("OFFLINE", 1, true))
        preview("core-" .. dimensions[1] .. "x" .. dimensions[2], f)
        send(f, runtime, "key", f.env.keys.enter)
        local shellId = runtime.kernel.foreground["local"]
        assert(shellId ~= coreId and runtime.kernel.getTask(shellId).parent == coreId)
        assert(runtime.kernel.getTask(shellId).status == "waiting")
        line(f, runtime, "login agent"); line(f, runtime, "change-me")
        local auth = runtime.services.get("auth")
        assert(auth.current(coreId).username == "agent" and auth.current(shellId).username == "agent")
        f.screen.reposition(1, 1, 18, 8)
        send(f, runtime, "term_resize")
        line(f, runtime, "exit")
        assert(runtime.kernel.foreground["local"] == coreId)
        assert(runtime.kernel.getTask(coreId).status == "waiting")
        assert(picture(f.screen):find("CORE", 1, true))
        send(f, runtime, "key", f.env.keys.enter)
        line(f, runtime, "logout")
        line(f, runtime, "exit")
        assert(auth.current(coreId) == nil)
        send(f, runtime, "key", f.env.keys.enter)
        send(f, runtime, "terminate")
        assert(runtime.kernel.foreground["local"] == coreId)
      end
    end
    local f = install("workstation", 26, 20, false)
    local runtime = boot(f)
    runtime.role.role = "pocket"
    send(f, runtime, "term_resize")
    line(f, runtime, "login agent"); line(f, runtime, "change-me")
    line(f, runtime, "clear")
    preview("field-mono-26x20", f)
    assert(picture(f.screen):find("FIELD", 1, true))
    send(f, runtime, "paste", "who")
    f.screen.reposition(1, 1, 12, 5)
    send(f, runtime, "term_resize")
    send(f, runtime, "paste", "ami")
    send(f, runtime, "key", f.env.keys.enter)
    assert(runtime.kernel.getTask(runtime.kernel.foreground["local"]).status == "waiting")
    assert(table.concat(f.output, "\n"):find("agent [clearance 2]", 1, true))
  end

  function tests.kernel_events_and_terminal_isolation()
    local f = install("workstation")
    local runtime = boot(f)
    local kernel = runtime.kernel
    local one = f.env.window.create(f.screen, 1, 4, 20, 4)
    local two = f.env.window.create(f.screen, 25, 4, 20, 4)
    local a = kernel.createTask("a", function()
      f.env.print("one")
      kernel.emit("test:internal")
      coroutine.yield("test:resume")
      f.env.print("one again")
    end, { terminal = one })
    local b = kernel.createTask("b", function()
      f.env.print("two")
      coroutine.yield("test:resume")
      f.env.print("two again")
    end, { terminal = two })
    assert(kernel.getTask(a).status == "waiting" and kernel.getTask(b).status == "waiting")
    drain(f, runtime)
    send(f, runtime, "test:resume")
    assert(kernel.getTask(a).status == "dead" and kernel.getTask(b).status == "dead")
    assert(picture(one):find("one again", 1, true) and not picture(one):find("two", 1, true))
    assert(picture(two):find("two again", 1, true) and not picture(two):find("one", 1, true))
    assert(f.env.term.current() == f.screen)
    local bad = kernel.createTask("invalid-yield", function() coroutine.yield({}) end)
    assert(kernel.getTask(bad).status == "error")
    assert(kernel.getTask(kernel.foreground["local"]).status == "waiting")
  end

  function tests.package_config_keep()
    local f = install("server")
    f.env.fs.makeDir("/aeon/packages/currency-management")
    local cfg = 'return { ledger_path = "/aeon/var/custom-ledger", card_reader = "saved" }'
    f.files["/aeon/etc/currency.cfg"] = cfg
    local packages = f.execute("/aeon/core/package.lua")
    assert(packages.installFromRepo("server", "currency-management"))
    assert(f.files["/aeon/etc/currency.cfg"] == cfg)
    assert(f.files["/aeon/apps/currency.lua"])
    assert(packages.getInstalled("currency-management").version == "1.2.0")
    -- The disk and repository paths use the same optional keep contract.
    f.files["/disk/aeon-package/manifest.lua"] = [[return {
      id="disk-test", version="1.0", files={
        {from="config.cfg",to="/aeon/etc/currency.cfg",mode="keep"},
      },
    }]]
    f.files["/disk/aeon-package/config.cfg"] = "return {}"
    assert(packages.installFromDisk("server", "/disk"))
    assert(f.files["/aeon/etc/currency.cfg"] == cfg)
  end

  function tests.package_surface_and_monitor()
    local f = install("server")
    f.env.fs.makeDir("/aeon/packages/example")
    f.files["/aeon/packages/example/manifest.lua"] = [[return {
      id = "example", version = "1.0", files = {
        { from = "drivers/example.lua", to = "/aeon/drivers/example.lua" },
      }, entrypoints = { drivers = { "example" } },
    }]]
    f.files["/aeon/packages/example/drivers/example.lua"] = [[return { id = "example",
      match = function() return true end,
      bindCapabilities = function() return { example = { query = function() return 42 end } } end,
    }]]
    assert(f.execute("/aeon/core/package.lua").installFromRepo("server", "example"))
    f.hardware.custom = { types = { "custom" }, object = {} }
    local runtime = boot(f)
    assert(runtime.devices.findCapability("example").call("query"))
    local display = f.execute("/aeon/drivers/display.lua")
    local view = f.execute("/aeon/core/ui.lua").create(display.create(f.screen), "aeon")
    local task = runtime.apps.start(f.execute("/aeon/apps/server.lua"), { ui = view, surface = "monitor" })
    assert(runtime.kernel.getTask(task).status == "waiting")
    assert(picture(f.screen):find("DISPLAY ONLY", 1, true))
    send(f, runtime, "key", f.env.keys.enter)
    assert(runtime.kernel.foreground.monitor == task)
    -- Migrated package app uses only UI, and consumes an existing shared identity.
    f = install("workstation")
    runtime = boot(f)
    line(f, runtime, "login agent"); line(f, runtime, "change-me")
    f.files["/aeon/apps/currency.lua"] = f.files["/aeon/packages/currency-management/apps/currency.lua"]
    if not f.files["/aeon/apps/currency.lua"] then
      local file = assert(io.open("aeon/packages/currency-management/apps/currency.lua"))
      f.files["/aeon/apps/currency.lua"] = file:read("*a"); file:close()
    end
    f.files["/aeon/lib/currency_api.lua"] = [[local api = {}
      for _, name in ipairs({"balance", "accounts", "ledger"}) do
        api[name] = function(runtime)
          packageUser = runtime.services.get("auth").current().username
          return { ok = false, message = "test offline" }
        end
      end
      return api]]
    local rootId = runtime.kernel.foreground["local"]
    line(f, runtime, "currency")
    assert(f.env.packageUser == "agent")
    assert(runtime.kernel.foreground["local"] ~= rootId)
    send(f, runtime, "char", "q")
    assert(runtime.kernel.foreground["local"] == rootId)
  end
end
