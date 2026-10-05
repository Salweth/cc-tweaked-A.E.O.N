local theme = {}

-- Only this module knows the CC colour palette. Text labels carry meaning on mono screens.
function theme.resolve(name, monochrome)
  local palette = {
    name = "aeon",
    text = colors.white,
    muted = colors.lightGray,
    accent = colors.cyan,
    success = colors.green,
    warning = colors.orange,
    error = colors.red,
    background = colors.black,
    border = colors.gray,
  }
  if type(name) == "table" then
    for role in pairs(palette) do
      if name[role] ~= nil then palette[role] = name[role] end
    end
  end
  -- The old unused "amber" setting is an alias; kept configs get the AEON identity too.
  if monochrome then
    for role in pairs(palette) do
      if role ~= "name" and role ~= "background" then palette[role] = colors.white end
    end
    palette.background = colors.black
  end
  return palette
end

return theme
