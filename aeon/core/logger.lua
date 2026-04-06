local logger = {
  state = {
    initialized = false,
    label = "LOG",
    level = "info",
    path = nil,
  }
}

local LEVELS = {
  debug = 1,
  info = 2,
  warn = 3,
  error = 4,
}

local function now()
  local day = os.day and os.day() or 0
  local time = textutils.formatTime(os.time(), true)
  return ("D%03d %s"):format(day, time)
end

local function shouldLog(level)
  local current = LEVELS[logger.state.level] or LEVELS.info
  local incoming = LEVELS[level] or LEVELS.info
  return incoming >= current
end

local function ensureParent(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function append(path, line)
  ensureParent(path)

  local handle = fs.open(path, fs.exists(path) and "a" or "w")
  if not handle then
    return false
  end

  handle.writeLine(line)
  handle.close()
  return true
end

local function emit(level, message)
  if not logger.state.initialized or not shouldLog(level) then
    return
  end

  local line = ("[%s] [%s] [%s] %s"):format(now(), logger.state.label, string.upper(level), tostring(message))

  print(line)

  if logger.state.path then
    append(logger.state.path, line)
  end
end

function logger.init(options)
  logger.state.initialized = true
  logger.state.label = options.label or logger.state.label
  logger.state.level = options.level or logger.state.level
  logger.state.path = options.path or logger.state.path
end

function logger.debug(message)
  emit("debug", message)
end

function logger.info(message)
  emit("info", message)
end

function logger.warn(message)
  emit("warn", message)
end

function logger.error(message)
  emit("error", message)
end

return logger
