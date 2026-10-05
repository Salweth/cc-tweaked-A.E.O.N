-- Character-cell terminal/window simulation with real clipping and scrollback boundaries.
return function(env, output, width, height, color)
  env.colors = { white = 1, orange = 2, cyan = 512, lightGray = 256,
    gray = 128, green = 8192, red = 16384, black = 32768 }
  env.keys = { enter = 28, backspace = 14, delete = 211, left = 203,
    right = 205, home = 199, ["end"] = 207 }
  local surfaces = {}
  local function terminal(w, h, parent, offsetX, offsetY)
    local target = { width = w, height = h, lines = {}, visible = true }
    surfaces[#surfaces + 1] = target
    local x, y, foreground, background = 1, 1, env.colors.white, env.colors.black
    local function blank() return { text = string.rep(" ", target.width), fg = {}, bg = {} } end
    for row = 1, h do target.lines[row] = blank() end
    local function paint(row)
      if not parent or not target.visible then return end
      parent.setCursorPos(offsetX, offsetY + row - 1)
      local line = target.lines[row]
      for col = 1, target.width do
        parent.setTextColor(line.fg[col] or foreground)
        parent.setBackgroundColor(line.bg[col] or background)
        parent.write(line.text:sub(col, col))
      end
    end
    function target.getSize() return target.width, target.height end
    function target.isColor() return color ~= false end
    function target.getCursorPos() return x, y end
    function target.setCursorPos(newX, newY) x, y = newX, newY end
    function target.setCursorBlink(value) target.blink = value end
    function target.setTextColor(value) assert(type(value) == "number"); foreground = value end
    function target.setBackgroundColor(value) assert(type(value) == "number"); background = value end
    function target.getTextColor() return foreground end
    function target.getBackgroundColor() return background end
    function target.write(text)
      assert(type(text) == "string")
      if y >= 1 and y <= target.height then
        local line = target.lines[y]
        for index = 1, #text do
          local col = x + index - 1
          if col >= 1 and col <= target.width then
            line.text = line.text:sub(1, col - 1) .. text:sub(index, index) .. line.text:sub(col + 1)
            line.fg[col], line.bg[col] = foreground, background
          end
        end
        paint(y)
      end
      x = x + #text
    end
    function target.clear()
      for row = 1, target.height do target.lines[row] = blank(); paint(row) end
    end
    function target.clearLine()
      if y >= 1 and y <= target.height then target.lines[y] = blank(); paint(y) end
    end
    function target.scroll(count)
      for _ = 1, count do table.remove(target.lines, 1); target.lines[#target.lines + 1] = blank() end
      target.redraw()
    end
    function target.redraw() for row = 1, target.height do paint(row) end end
    function target.setVisible(value) target.visible = value; if value then target.redraw() end end
    function target.reposition(newX, newY, newWidth, newHeight)
      offsetX, offsetY = newX, newY
      target.width, target.height = newWidth or target.width, newHeight or target.height
      for row = 1, target.height do
        target.lines[row] = target.lines[row] or blank()
        target.lines[row].text = (target.lines[row].text .. string.rep(" ", target.width)):sub(1, target.width)
      end
      for row = #target.lines, target.height + 1, -1 do target.lines[row] = nil end
      x, y = math.min(x, target.width), math.min(y, target.height)
      target.redraw()
    end
    return target
  end
  local screen = terminal(width or 51, height or 19)
  local current = screen
  env.term = { current = function() return current end, native = function() return screen end,
    redirect = function(target) assert(target); local old = current; current = target; return old end }
  setmetatable(env.term, { __index = function(_, method)
    return function(...) return current[method](...) end
  end })
  env.window = { create = function(parent, x, y, w, h)
    assert(w >= 1 and h >= 1)
    return terminal(w, h, parent, x, y)
  end }
  env.write = function(value)
    local text = tostring(value)
    local w, h = current.getSize()
    local x, y = current.getCursorPos()
    local function newline()
      x, y = 1, y + 1
      if y > h then current.scroll(1); y = h end
      current.setCursorPos(x, y)
    end
    for index = 1, #text do
      local ch = text:sub(index, index)
      if ch == "\n" then newline()
      else
        if x > w then newline() end
        current.setCursorPos(x, y); current.write(ch); x = x + 1
      end
    end
    current.setCursorPos(x, y)
  end
  env.print = function(...)
    local args = {}
    for i = 1, select("#", ...) do args[i] = tostring(select(i, ...)) end
    local line = table.concat(args, "\t")
    output[#output + 1] = line
    env.write(line .. "\n")
  end
  return screen, surfaces
end
