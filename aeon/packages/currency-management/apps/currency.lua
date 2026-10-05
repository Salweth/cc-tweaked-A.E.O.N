local define = dofile("/aeon/core/app.lua").define
local currency = dofile("/aeon/lib/currency_api.lua")

local function header(runtime)
  local root = runtime.ui
  local function layout()
    local width, height = root.size()
    local rows = math.min(3, math.max(0, height - 3))
    if runtime.currency_ui then
      runtime.currency_ui.backend.resize(1, rows + 1, width, height - rows)
    else
      runtime.currency_ui = root.region(1, rows + 1, width, height - rows)
    end
    for row = 1, rows do root.at(1, row, string.rep(" ", width)) end
    root.header("CURRENCY", runtime.hostname, rows)
  end
  root.clear()
  layout()
  runtime.currency_ui.clear()
  runtime.currency_ui.setEventHandler(function(event)
    if event[1] == "term_resize" or event[1] == "monitor_resize" then layout() end
  end)
end

local function waitKey(runtime)
  runtime.currency_ui.print("")
  runtime.currency_ui.print("Press any key to continue.")
  runtime.currency_ui.wait("key")
end

local function promptTransfer(runtime)
  header(runtime)
  local target = runtime.currency_ui.read({ prompt = "Target account ID: " })
  local amount = tonumber(runtime.currency_ui.read({ prompt = "Amount: " }))
  local reason = runtime.currency_ui.read({ prompt = "Reason: " })

  local result = currency.transfer(runtime, target, amount, reason)
  runtime.currency_ui.print("")
  if result.ok then
    runtime.currency_ui.print(("transfer complete, new balance: %s"):format(tostring(result.data.formatted or result.data.balance)))
  else
    runtime.currency_ui.print(("transfer failed: %s"):format(tostring(result.message)))
  end
  waitKey(runtime)
end

local function showHistory(runtime)
  header(runtime)
  local result = currency.ledger(runtime)
  runtime.currency_ui.print("Recent audit:")
  runtime.currency_ui.print("")
  if result.ok then
    for _, item in ipairs(result.data.transactions or {}) do
      runtime.currency_ui.print(("%s -> %s : %s"):format(
        tostring(item.actor),
        tostring(item.target_id),
        tostring(item.amount)
      ))
      runtime.currency_ui.print(("  %s"):format(tostring(item.reason or "no reason")))
    end
  else
    runtime.currency_ui.print(("history unavailable: %s"):format(tostring(result.message)))
  end
  waitKey(runtime)
end

local function dashboard(runtime)
  local balance = currency.balance(runtime)
  local accounts = currency.accounts(runtime)
  local ledger = currency.ledger(runtime)

  header(runtime)
  if balance.ok then
    runtime.currency_ui.print(("Trade Link Balance: %s"):format(tostring(balance.data.formatted or balance.data.balance)))
  else
    runtime.currency_ui.print(("Trade Link Balance: %s"):format(tostring(balance.message)))
  end

  runtime.currency_ui.print("")
  runtime.currency_ui.print("Known accounts:")
  if accounts.ok and accounts.data and #(accounts.data.accounts or {}) > 0 then
    for i = 1, math.min(3, #accounts.data.accounts) do
      local item = accounts.data.accounts[i]
      runtime.currency_ui.print(("- [%s] %s"):format(tostring(item.id), tostring(item.label)))
    end
  else
    runtime.currency_ui.print("- no accounts available")
  end

  runtime.currency_ui.print("")
  runtime.currency_ui.print("Recent activity:")
  if ledger.ok and ledger.data and #(ledger.data.transactions or {}) > 0 then
    for i = 1, math.min(3, #ledger.data.transactions) do
      local item = ledger.data.transactions[i]
      runtime.currency_ui.print(("- %s -> %s : %s"):format(
        tostring(item.actor),
        tostring(item.target_id),
        tostring(item.amount)
      ))
    end
  else
    runtime.currency_ui.print("- no recent transactions")
  end

  runtime.currency_ui.print("")
  runtime.currency_ui.print("Actions:")
  runtime.currency_ui.print("[1] Transfer")
  runtime.currency_ui.print("[2] History")
  runtime.currency_ui.print("[Q] Quit")
end

local app = define({
  name = "currency",
  run = function(runtime)
    while true do
      dashboard(runtime)
      local _, key = runtime.currency_ui.wait("char")
      if key == "1" then
        promptTransfer(runtime)
      elseif key == "2" then
        showHistory(runtime)
      elseif key == "q" or key == "Q" then
        runtime.ui.clear()
        return
      end
    end
  end,
})

return app
