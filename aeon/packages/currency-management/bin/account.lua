local currency = dofile("/aeon/lib/currency_api.lua")

local command = {}

function command.run(context, args)
  local mode = args[1] or "list"
  if mode ~= "list" then
    print("usage: account [list]")
    return
  end

  local result = currency.accounts(context.runtime)
  if not result.ok then
    print(("account list failed: %s"):format(tostring(result.message)))
    return
  end

  for _, account in ipairs(result.data.accounts or {}) do
    print(("[%s] %s"):format(tostring(account.id), tostring(account.label)))
  end
end

return command
