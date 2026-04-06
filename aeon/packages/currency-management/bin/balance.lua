local currency = dofile("/aeon/lib/currency_api.lua")

local command = {}

function command.run(context, args)
  local result = currency.balance(context.runtime, args[1])
  if not result.ok then
    print(("balance failed: %s"):format(tostring(result.message)))
    return
  end

  print(("account: %s"):format(tostring(result.data.account.id)))
  print(("balance: %s cr"):format(tostring(result.data.balance)))
end

return command
