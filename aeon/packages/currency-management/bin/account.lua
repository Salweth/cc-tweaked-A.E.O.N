local currency = dofile("/aeon/lib/currency_api.lua")

local command = {}

local function joinName(args, startIndex)
  local value = table.concat(args, " ", startIndex)
  value = string.gsub(value, '^"', "")
  value = string.gsub(value, '"$', "")
  return value
end

function command.run(context, args)
  local mode = args[1] or "list"

  if mode == "list" then
    local result = currency.accounts(context.runtime)
    if not result.ok then
      print(("account list failed: %s"):format(tostring(result.message)))
      return
    end

    for _, account in ipairs(result.data.accounts or {}) do
      print(("%-18s %8s locked=%s"):format(
        tostring(account.id),
        tostring(account.balance),
        tostring(account.locked)
      ))
    end
    return
  end

  if mode == "create" then
    local id = args[2]
    local name = joinName(args, 3)
    if not id or name == "" then
      print('usage: account create <id> "<name>"')
      return
    end

    local result = currency.createAccount(context.runtime, id, name)
    if not result.ok then
      print(("account create failed: %s"):format(tostring(result.message)))
      return
    end

    print(("created account %s"):format(id))
    return
  end

  if mode == "lock" or mode == "unlock" then
    local id = args[2]
    if not id then
      print(("usage: account %s <id>"):format(mode))
      return
    end

    local result = currency.lockAccount(context.runtime, id, mode == "lock")
    if not result.ok then
      print(("account update failed: %s"):format(tostring(result.message)))
      return
    end

    print(("%s %s"):format(mode, id))
    return
  end

  print('usage: account [list|create <id> "<name>"|lock <id>|unlock <id>]')
end

return command
