local shell = dofile("/aeon/shell/shell.lua")
local define = dofile("/aeon/core/app.lua").define

local app = define({
  name = "terminal",
  run = function(runtime)
    shell.run(runtime)
  end,
})

return app
