local define = dofile("/aeon/core/app.lua").define
local currency = dofile("/aeon/lib/currency_api.lua")

local function currentUser(runtime)
  local auth = runtime.services.get("auth")
  local session = auth and auth.current() or nil
  return session and session.username or "anonymous"
end

local function header()
  term.clear()
  term.setCursorPos(1, 1)
  print("AEON // CURRENCY MANAGEMENT")
  print("")
end

local function waitKey()
  print("")
  print("Press any key to continue.")
  os.pullEvent("key")
end

local function showHistory(runtime, accountId)
  header()
  local result = currency.ledger(runtime, accountId)
  print(("Account: %s"):format(accountId))
  print("")
  if result.ok then
    for _, item in ipairs(result.data.transactions or {}) do
      print(("%s -> %s : %s"):format(
        tostring(item.from),
        tostring(item.to),
        tostring(item.amount)
      ))
      print(("  %s"):format(tostring(item.reason or "no reason")))
    end
  else
    print(("history unavailable: %s"):format(tostring(result.message)))
  end
  waitKey()
end

local function promptTransfer(runtime)
  header()
  write("Target account: ")
  local target = read()
  write("Amount: ")
  local amount = tonumber(read())
  write("Reason: ")
  local reason = read()

  local result = currency.transfer(runtime, target, amount, reason)
  print("")
  if result.ok then
    print(("transfer complete, new balance: %s cr"):format(tostring(result.data.balance)))
  else
    print(("transfer failed: %s"):format(tostring(result.message)))
  end
  waitKey()
end

local function dashboard(runtime)
  local accountId = currentUser(runtime)
  local balance = currency.balance(runtime, accountId)
  local ledger = currency.ledger(runtime, accountId)

  header()
  print(("Account: %s"):format(accountId))
  if balance.ok then
    print(("Balance: %s cr"):format(tostring(balance.data.balance)))
  else
    print(("Balance: %s"):format(tostring(balance.message)))
  end

  print("")
  print("Recent activity:")
  if ledger.ok and ledger.data and #(ledger.data.transactions or {}) > 0 then
    for i = 1, math.min(3, #ledger.data.transactions) do
      local item = ledger.data.transactions[i]
      print(("- %s -> %s : %s"):format(
        tostring(item.from),
        tostring(item.to),
        tostring(item.amount)
      ))
    end
  else
    print("- no recent transactions")
  end

  print("")
  print("Actions:")
  print("[1] Transfer")
  print("[2] History")
  print("[Q] Quit")
end

local app = define({
  name = "currency",
  run = function(runtime)
    while true do
      local accountId = currentUser(runtime)
      dashboard(runtime)
      local _, key = os.pullEvent("char")
      if key == "1" then
        promptTransfer(runtime)
      elseif key == "2" then
        showHistory(runtime, accountId)
      elseif key == "q" or key == "Q" then
        term.clear()
        term.setCursorPos(1, 1)
        return
      end
    end
  end,
})

return app
