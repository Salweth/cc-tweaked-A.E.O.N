local currency = dofile("/aeon/lib/currency_api.lua")

local command = {}

function command.run(context, args)
  local target = args[1]
  local amount = tonumber(args[2])
  local reason = table.concat(args, " ", 3)

  if not target or not amount then
    print("usage: transfer <target> <amount> [reason]")
    return
  end

  local result = currency.transfer(
    context.runtime,
    target,
    amount,
    reason ~= "" and reason or "manual transfer"
  )

  if not result.ok then
    print(("transfer failed: %s"):format(tostring(result.message)))
    return
  end

  print(("transfer complete, new balance: %s cr"):format(tostring(result.data.balance)))
end

return command
