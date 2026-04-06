local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")
local currencyDriver = dofile("/aeon/drivers/currency.lua")

local function nowUtc()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function readTable(path, fallback)
  if not fs.exists(path) or fs.isDir(path) then
    return fallback
  end

  local ok, result = pcall(dofile, path)
  if not ok or type(result) ~= "table" then
    return fallback
  end

  return result
end

local function writeTable(path, value)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end

  local handle = fs.open(path, "w")
  if not handle then
    return false, ("unable to write %s"):format(path)
  end

  handle.write("return ")
  handle.write(textutils.serialize(value, { compact = false }))
  handle.write("\n")
  handle.close()
  return true
end

local function loadConfig()
  if fs.exists("/aeon/etc/currency.cfg") then
    return dofile("/aeon/etc/currency.cfg")
  end

  return {
    card_reader = nil,
    ledger_path = "/aeon/var/currency/ledger.db",
  }
end

local function success(data)
  return { ok = true, data = data or {} }
end

local function failure(code, message)
  return { ok = false, error = code, message = message }
end

local service = define({
  name = "currency",
  essential = false,
  start = function(context)
    if context.role.role ~= "server" then
      context.log.info("currency service idle on non-server node")
      return {}
    end

    local cfg = loadConfig()
    local net = context.services.get("net")
    local ledgerDb = readTable(cfg.ledger_path, { transactions = {} })

    local function saveLedger()
      return writeTable(cfg.ledger_path, ledgerDb)
    end

    local function resolveReader()
      if cfg.card_reader and context.registry.get(cfg.card_reader) then
        return context.registry.get(cfg.card_reader)
      end
      return currencyDriver.detect(context.registry)
    end

    local function withReader()
      local reader = resolveReader()
      if not reader or not reader.object then
        return nil, failure("READER_UNAVAILABLE", "Trade Link card reader unavailable.")
      end
      return reader.object
    end

    local function appendTransaction(actor, targetId, amount, reason, status)
      table.insert(ledgerDb.transactions, 1, {
        id = ("tx-%s-%s"):format(nowUtc(), math.random(1000, 9999)),
        actor = actor,
        target_id = targetId,
        amount = amount,
        reason = reason,
        status = status,
        timestamp = nowUtc(),
      })
    end

    local function getBalance()
      local reader, err = withReader()
      if not reader then
        return err
      end
      if type(reader.GetBalance) ~= "function" or type(reader.GetNumericalBalance) ~= "function" then
        return failure("UNSUPPORTED_READER", "Trade Link balance methods unavailable.")
      end

      return success({
        formatted = reader.GetBalance(),
        balance = reader.GetNumericalBalance(),
      })
    end

    local function listAccounts()
      local reader, err = withReader()
      if not reader then
        return err
      end
      if type(reader.getAllAccounts) ~= "function" then
        return failure("UNSUPPORTED_READER", "Trade Link account listing unavailable.")
      end

      local rawAccounts = reader.getAllAccounts() or {}
      local items = {}
      for index, item in ipairs(rawAccounts) do
        table.insert(items, {
          id = index,
          label = tostring(item),
        })
      end

      return success({ accounts = items })
    end

    local function transfer(actor, targetId, amount, reason)
      local reader, err = withReader()
      if not reader then
        return err
      end
      if type(reader.payAccount) ~= "function" then
        return failure("UNSUPPORTED_READER", "Trade Link payment unavailable.")
      end

      local accountId = tonumber(targetId)
      amount = tonumber(amount)
      if not accountId then
        return failure("INVALID_ACCOUNT", "Target account ID must be numeric.")
      end
      if not amount or amount <= 0 then
        return failure("INVALID_AMOUNT", "Amount must be greater than zero.")
      end

      local ok, callResult = pcall(reader.payAccount, accountId, amount)
      if not ok then
        appendTransaction(actor, accountId, amount, reason or "manual transfer", "failed")
        saveLedger()
        return failure("TRANSFER_FAILED", tostring(callResult))
      end

      appendTransaction(actor, accountId, amount, reason or "manual transfer", "ok")
      saveLedger()

      local balance = getBalance()
      if not balance.ok then
        return success({
          result = callResult,
        })
      end

      return success({
        result = callResult,
        formatted = balance.data.formatted,
        balance = balance.data.balance,
      })
    end

    local function getLedger(actor, targetId)
      local items = {}
      for _, item in ipairs(ledgerDb.transactions or {}) do
        if not targetId or tostring(item.target_id) == tostring(targetId) or item.actor == actor then
          table.insert(items, item)
        end
        if #items >= 10 then
          break
        end
      end

      return success({ transactions = items })
    end

    context.on(events.global("net.request.currency.balance"), function(event)
      local payload = event[2]
      net.respond(payload, getBalance())
    end)

    context.on(events.global("net.request.currency.accounts"), function(event)
      local payload = event[2]
      net.respond(payload, listAccounts())
    end)

    context.on(events.global("net.request.currency.transfer"), function(event)
      local payload = event[2]
      local data = payload.data or {}
      net.respond(payload, transfer(data.actor, data.target_id, data.amount, data.reason))
    end)

    context.on(events.global("net.request.currency.ledger"), function(event)
      local payload = event[2]
      local data = payload.data or {}
      net.respond(payload, getLedger(data.actor, data.account_id))
    end)

    context.log.info("currency service online")

    return {
      getBalance = getBalance,
      listAccounts = listAccounts,
      transfer = transfer,
      getLedger = getLedger,
    }
  end,
})

return service
