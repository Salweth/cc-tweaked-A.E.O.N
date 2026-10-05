local themes = dofile("/aeon/core/theme.lua")
local ui = {}

local STATUS_ROLES = {
  ONLINE = "success", LINKED = "accent", NOMINAL = "accent", OFFLINE = "muted",
  WARNING = "warning", CRITICAL = "error", RESTRICTED = "warning",
}

function ui.truncate(value, width)
  local text = tostring(value or ""):gsub("[\r\n\t]", " ")
  width = math.max(0, math.floor(width))
  if #text <= width then return text end
  if width <= 3 then return text:sub(1, width) end
  return text:sub(1, width - 3) .. "..."
end

function ui.create(backend, theme)
  local view = { backend = backend, theme = themes.resolve(theme, not backend.isColor()) }
  local onEvent = nil
  function view.size() return backend.size() end
  function view.clear() backend.clear(view.theme.text, view.theme.background) end
  function view.cursor(x, y) backend.cursor(x, y) end
  function view.at(x, y, text, role, width)
    local w, h = view.size()
    if x < 1 or y < 1 or x > w or y > h then return end
    local clipped = ui.truncate(text, math.min(width or w, w - x + 1))
    backend.text(x, y, clipped, view.theme[role or "text"] or view.theme.text, view.theme.background)
  end
  function view.separator(y)
    local width = view.size()
    view.at(1, y, string.rep("-", width), "border")
  end
  function view.header(surface, identity, rows)
    local _, height = view.size()
    rows = math.min(rows or 3, height)
    if rows >= 1 then view.at(1, 1, "A.E.O.N. // " .. surface, "accent") end
    if rows >= 2 then view.at(1, 2, identity or "", "muted") end
    if rows >= 3 then view.separator(3) end
    return rows + 1
  end
  function view.label(y, label, value, role)
    local width = view.size()
    local column = math.min(13, math.max(2, math.floor(width * 0.4)))
    if width < 12 then
      view.at(1, y, tostring(label) .. " " .. tostring(value), role)
    else
      view.at(1, y, label, "muted", column - 2)
      view.at(column, y, value, role)
    end
  end
  function view.status(y, label, status)
    view.label(y, label, status, STATUS_ROLES[status] or "text")
  end
  function view.print(...)
    backend.tone(view.theme.text, view.theme.background)
    return backend.print(...)
  end
  function view.write(text, role)
    backend.tone(view.theme[role or "text"], view.theme.background)
    return backend.write(tostring(text))
  end
  function view.withTerminal(fn, ...)
    backend.tone(view.theme.text, view.theme.background)
    return backend.withTerminal(fn, ...)
  end
  function view.region(x, y, width, height)
    return ui.create(backend.region(x, y, width, height), view.theme)
  end
  function view.setEventHandler(handler) onEvent = handler end
  function view.wait(filter)
    while true do
      local event = table.pack(coroutine.yield())
      if event[1] == "terminate" then error("Terminated", 0) end
      if onEvent then onEvent(event) end
      if not filter or event[1] == filter then return table.unpack(event, 1, event.n) end
    end
  end
  -- A small keyboard line editor: no terminal-global read or OS-event replacement.
  function view.read(options)
    options = options or {}
    if not backend.input then return nil, "surface has no keyboard input" end
    local text, position = "", 0
    local _, row = backend.position()
    local function render()
      local width, height = view.size()
      row = math.max(1, math.min(row, height))
      local prompt = type(options.prompt) == "function" and options.prompt() or options.prompt or ""
      prompt = ui.truncate(prompt, math.max(0, width - math.min(8, width)))
      local available = math.max(1, width - #prompt)
      local offset = math.max(0, position - available + 1)
      local shown = options.mask and string.rep(options.mask:sub(1, 1), #text) or text
      view.at(1, row, string.rep(" ", width))
      view.at(1, row, prompt, "accent")
      -- Input uses horizontal scrolling, not an ellipsis inside the editable value.
      backend.text(#prompt + 1, row, shown:sub(offset + 1, offset + available), view.theme.text, view.theme.background)
      backend.cursor(math.min(width, #prompt + position - offset + 1), row)
      backend.blink(true)
    end
    render()
    while true do
      local event = table.pack(coroutine.yield())
      if event[1] == "terminate" then backend.blink(false); error("Terminated", 0) end
      if onEvent then onEvent(event) end
      if event[1] == "char" or event[1] == "paste" then
        local value = tostring(event[2]):gsub("[\r\n]", "")
        text = text:sub(1, position) .. value .. text:sub(position + 1)
        position = position + #value
      elseif event[1] == "key" then
        local key = event[2]
        if key == keys.enter then
          backend.blink(false)
          backend.print("")
          return text
        elseif key == keys.backspace and position > 0 then
          text = text:sub(1, position - 1) .. text:sub(position + 1)
          position = position - 1
        elseif key == keys.delete then
          text = text:sub(1, position) .. text:sub(position + 2)
        elseif key == keys.left then position = math.max(0, position - 1)
        elseif key == keys.right then position = math.min(#text, position + 1)
        elseif key == keys.home then position = 0
        elseif key == keys["end"] then position = #text end
      end
      render()
    end
  end
  return view
end

return ui
