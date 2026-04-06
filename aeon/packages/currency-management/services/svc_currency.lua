local define = dofile("/aeon/core/service_contract.lua").define

local service = define({
  name = "currency",
  essential = false,
  start = function(context)
    context.log.info("currency package scaffold online")
    return {
      status = function()
        return "scaffold"
      end,
    }
  end,
})

return service
