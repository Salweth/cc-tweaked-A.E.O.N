local currency = dofile("/aeon/lib/currency_api.lua")

local command = {}

function command.run(context, _args)
  local result = currency.balance(context.runtime)
  if not result.ok then
    print(("balance failed: %s"):format(tostring(result.message)))
    return
  end

  print(("balance: %s"):format(tostring(result.data.formatted or result.data.balance)))
end

return command
