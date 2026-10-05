local driver = { id = "cc.monitor" }

function driver.match(entry, helpers)
  return helpers.hasType(entry, "monitor")
    and helpers.hasMethods(entry, { "write", "clear", "setCursorPos", "getSize" })
end

function driver.bindCapabilities(entry)
  return { display = entry.object, monitor = entry.object }
end

function driver.bind(termObject)
  return termObject or term.current()
end

function driver.current()
  return term.current()
end

function driver.activate(target)
  return term.redirect(target)
end

function driver.withTerminal(target, fn, ...)
  local previous = driver.activate(target)
  local result = table.pack(pcall(fn, ...))
  driver.activate(previous)
  if not result[1] then error(result[2], 0) end
  return table.unpack(result, 2, result.n)
end

-- A terminal-shaped target may come from CC, a monitor, or a later adapter.
function driver.create(target, options)
  options = options or {}
  local backend = { terminal = driver.bind(target), input = options.input == true }
  local surface = backend.terminal
  function backend.size() return surface.getSize() end
  function backend.isColor() return not surface.isColor or surface.isColor() end
  function backend.cursor(x, y) return surface.setCursorPos(x, y) end
  function backend.position() return surface.getCursorPos() end
  function backend.blink(value)
    if surface.setCursorBlink then surface.setCursorBlink(value) end
  end
  function backend.tone(foreground, background)
    if surface.setTextColor then surface.setTextColor(foreground) end
    if surface.setBackgroundColor then surface.setBackgroundColor(background) end
  end
  function backend.clear(foreground, background)
    backend.tone(foreground, background)
    surface.clear()
    backend.cursor(1, 1)
  end
  function backend.text(x, y, text, foreground, background)
    local oldX, oldY = backend.position()
    local oldForeground = surface.getTextColor and surface.getTextColor()
    local oldBackground = surface.getBackgroundColor and surface.getBackgroundColor()
    backend.tone(foreground, background)
    backend.cursor(x, y)
    surface.write(text)
    backend.cursor(oldX, oldY)
    if oldForeground and oldBackground then backend.tone(oldForeground, oldBackground) end
  end
  function backend.print(...) return driver.withTerminal(surface, print, ...) end
  function backend.write(text) return driver.withTerminal(surface, write, text) end
  function backend.withTerminal(fn, ...) return driver.withTerminal(surface, fn, ...) end
  function backend.region(x, y, width, height)
    assert(window and window.create, "CC window API required for terminal regions")
    return driver.create(window.create(surface, x, y, width, height), { input = backend.input })
  end
  function backend.resize(x, y, width, height)
    assert(surface.reposition, "backend does not support repositioning")
    surface.reposition(x, y, width, height)
  end
  function backend.visible(value)
    if surface.setVisible then surface.setVisible(value) end
  end
  function backend.redraw()
    if surface.redraw then surface.redraw() end
  end
  return backend
end

-- Capability calls remain protected and expire when the physical registry refreshes.
function driver.fromCapability(provider, options)
  local target = setmetatable({}, { __index = function(_, method)
    return function(...)
      local current = type(provider) == "function" and provider() or provider
      if not current then error("display unavailable", 0) end
      local result = table.pack(current.call(method, ...))
      if not result[1] then error(result[2], 0) end
      return table.unpack(result, 2, result.n)
    end
  end })
  return driver.create(target, options)
end

return driver
