local shell = dofile("/aeon/shell/shell.lua")

local app = {}

function app.run(runtime)
  shell.run(runtime)
end

return app
