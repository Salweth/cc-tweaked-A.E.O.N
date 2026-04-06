local define = dofile("/aeon/core/app.lua").define
local currency = dofile("/aeon/lib/currency_api.lua")

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

local function promptTransfer(runtime)
  header()
  write("Target account ID: ")
  local target = read()
  write("Amount: ")
  local amount = tonumber(read())
  write("Reason: ")
  local reason = read()

  local result = currency.transfer(runtime, target, amount, reason)
  print("")
  if result.ok then
    print(("transfer complete, new balance: %s"):format(tostring(result.data.formatted or result.data.balance)))
  else
    print(("transfer failed: %s"):format(tostring(result.message)))
  end
  waitKey()
end

local function showHistory(runtime)
  header()
  local result = currency.ledger(runtime)
  print("Recent audit:")
  print("")
  if result.ok then
    for _, item in ipairs(result.data.transactions or {}) do
      print(("%s -> %s : %s"):format(
        tostring(item.actor),
        tostring(item.target_id),
        tostring(item.amount)
      ))
      print(("  %s"):format(tostring(item.reason or "no reason")))
    end
  else
    print(("history unavailable: %s"):format(tostring(result.message)))
  end
  waitKey()
end

local function dashboard(runtime)
  local balance = currency.balance(runtime)
  local accounts = currency.accounts(runtime)
  local ledger = currency.ledger(runtime)

  header()
  if balance.ok then
    print(("Trade Link Balance: %s"):format(tostring(balance.data.formatted or balance.data.balance)))
  else
    print(("Trade Link Balance: %s"):format(tostring(balance.message)))
  end

  print("")
  print("Known accounts:")
  if accounts.ok and accounts.data and #(accounts.data.accounts or {}) > 0 then
    for i = 1, math.min(3, #accounts.data.accounts) do
      local item = accounts.data.accounts[i]
      print(("- [%s] %s"):format(tostring(item.id), tostring(item.label)))
    end
  else
    print("- no accounts available")
  end

  print("")
  print("Recent activity:")
  if ledger.ok and ledger.data and #(ledger.data.transactions or {}) > 0 then
    for i = 1, math.min(3, #ledger.data.transactions) do
      local item = ledger.data.transactions[i]
      print(("- %s -> %s : %s"):format(
        tostring(item.actor),
        tostring(item.target_id),
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
      dashboard(runtime)
      local _, key = os.pullEvent("char")
      if key == "1" then
        promptTransfer(runtime)
      elseif key == "2" then
        showHistory(runtime)
      elseif key == "q" or key == "Q" then
        term.clear()
        term.setCursorPos(1, 1)
        return
      end
    end
  end,
})

return app
