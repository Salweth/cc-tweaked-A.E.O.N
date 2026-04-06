local currency = dofile("/aeon/lib/currency_api.lua")

local command = {}

function command.run(context, args)
  local result = currency.ledger(context.runtime, args[1])
  if not result.ok then
    print(("ledger failed: %s"):format(tostring(result.message)))
    return
  end

  for _, item in ipairs(result.data.transactions or {}) do
    print(("%s -> %s : %s [%s]"):format(
      tostring(item.actor),
      tostring(item.target_id),
      tostring(item.amount),
      tostring(item.reason or "no reason")
    ))
  end
end

return command
