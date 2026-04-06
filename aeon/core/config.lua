local config = {}

local function fileExists(path)
  return fs.exists(path) and not fs.isDir(path)
end

function config.load(path)
  if not fileExists(path) then
    return {}
  end

  local ok, chunk = pcall(dofile, path)
  if not ok then
    error(("invalid config file %s: %s"):format(path, tostring(chunk)), 0)
  end

  if type(chunk) ~= "table" then
    error(("config file %s must return a table"):format(path), 0)
  end

  return chunk
end

return config
