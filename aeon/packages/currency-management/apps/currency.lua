local define = dofile("/aeon/core/app.lua").define

local app = define({
  name = "currency",
  run = function(_runtime)
    term.clear()
    term.setCursorPos(1, 1)
    print("A.E.O.N CURRENCY MANAGEMENT")
    print("")
    print("Package scaffold installed.")
    print("Lightman's Currency backend is not wired yet.")
    print("")
    print("Use `balance` and `transfer` once the service is connected.")
  end,
})

return app
