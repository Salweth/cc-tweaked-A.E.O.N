local define = dofile("/aeon/core/service_contract.lua").define
local events = dofile("/aeon/core/events.lua")

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
    accounts_path = "/aeon/var/currency/accounts.db",
    ledger_path = "/aeon/var/currency/ledger.db",
  }
end

local function success(data)
  return {
    ok = true,
    data = data or {},
  }
end

local function failure(code, message)
  return {
    ok = false,
    error = code,
    message = message,
  }
end

local function hasRole(session, role)
  for _, item in ipairs(session and session.roles or {}) do
    if item == role then
      return true
    end
  end
  return false
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
    local auth = context.services.get("auth")
    local net = context.services.get("net")
    local accountsDb = readTable(cfg.accounts_path, {
      accounts = {
        ["server-core"] = {
          id = "server-core",
          name = "Server Core",
          balance = 100000,
          role = "system",
          clearance = 5,
          locked = false,
        }
      }
    })
    local ledgerDb = readTable(cfg.ledger_path, {
      transactions = {}
    })

    local function save()
      local ok, err = writeTable(cfg.accounts_path, accountsDb)
      if not ok then
        return false, err
      end

      ok, err = writeTable(cfg.ledger_path, ledgerDb)
      if not ok then
        return false, err
      end

      return true
    end

    local function sessionFor(actor)
      if not actor then
        return nil
      end
      for _, session in ipairs(auth and auth.listSessions() or {}) do
        if session.username == actor then
          return session
        end
      end
      return nil
    end

    local function canAdmin(actor)
      return hasRole(sessionFor(actor), "admin")
    end

    local function canRead(actor, target)
      local session = sessionFor(actor)
      return session and (session.username == target or hasRole(session, "admin")) or false
    end

    local function getBalance(accountId, actor)
      local target = accountId or actor
      if not target then
        return failure("AUTH_REQUIRED", "Authentication required.")
      end
      if not canRead(actor, target) then
        return failure("PERMISSION_DENIED", "You cannot read this account.")
      end

      local account = accountsDb.accounts[target]
      if not account then
        return failure("ACCOUNT_NOT_FOUND", "Account not found.")
      end

      return success({
        account = account,
        balance = account.balance,
      })
    end

    local function appendTransaction(fromId, toId, amount, actor, reason)
      table.insert(ledgerDb.transactions, 1, {
        id = ("tx-%s-%s"):format(nowUtc(), math.random(1000, 9999)),
        from = fromId,
        to = toId,
        amount = amount,
        actor = actor,
        reason = reason,
        timestamp = nowUtc(),
      })
    end

    local function transfer(actor, targetId, amount, reason)
      if not actor then
        return failure("AUTH_REQUIRED", "Authentication required.")
      end

      amount = tonumber(amount)
      if not amount or amount <= 0 then
        return failure("INVALID_AMOUNT", "Amount must be greater than zero.")
      end

      local fromAccount = accountsDb.accounts[actor]
      local toAccount = accountsDb.accounts[targetId]
      if not fromAccount or not toAccount then
        return failure("ACCOUNT_NOT_FOUND", "Account not found.")
      end
      if fromAccount.locked or toAccount.locked then
        return failure("ACCOUNT_LOCKED", "One of the accounts is locked.")
      end
      if fromAccount.balance < amount then
        return failure("INSUFFICIENT_FUNDS", "Balance too low for requested transfer.")
      end

      fromAccount.balance = fromAccount.balance - amount
      toAccount.balance = toAccount.balance + amount
      appendTransaction(actor, targetId, amount, actor, reason or "manual transfer")
      local ok, err = save()
      if not ok then
        return failure("STORAGE_ERROR", err)
      end

      return success({
        balance = fromAccount.balance,
      })
    end

    local function listAccounts(actor)
      if not canAdmin(actor) then
        return failure("PERMISSION_DENIED", "Admin permission required.")
      end

      local items = {}
      for _, account in pairs(accountsDb.accounts) do
        table.insert(items, account)
      end
      table.sort(items, function(a, b) return a.id < b.id end)
      return success({ accounts = items })
    end

    local function createAccount(actor, id, name)
      if not canAdmin(actor) then
        return failure("PERMISSION_DENIED", "Admin permission required.")
      end
      if not id or id == "" or not name or name == "" then
        return failure("INVALID_ACCOUNT", "Account id and name are required.")
      end
      if accountsDb.accounts[id] then
        return failure("ACCOUNT_EXISTS", "Account already exists.")
      end

      accountsDb.accounts[id] = {
        id = id,
        name = name,
        balance = 0,
        role = "field",
        clearance = 1,
        locked = false,
      }

      local ok, err = save()
      if not ok then
        return failure("STORAGE_ERROR", err)
      end

      return success({ account = accountsDb.accounts[id] })
    end

    local function setLocked(actor, id, locked)
      if not canAdmin(actor) then
        return failure("PERMISSION_DENIED", "Admin permission required.")
      end
      local account = accountsDb.accounts[id]
      if not account then
        return failure("ACCOUNT_NOT_FOUND", "Account not found.")
      end

      account.locked = locked and true or false
      local ok, err = save()
      if not ok then
        return failure("STORAGE_ERROR", err)
      end

      return success({ account = account })
    end

    local function getLedger(actor, accountId)
      local target = accountId or actor
      if not target then
        return failure("AUTH_REQUIRED", "Authentication required.")
      end
      if not canRead(actor, target) then
        return failure("PERMISSION_DENIED", "You cannot read this ledger.")
      end

      local items = {}
      for _, item in ipairs(ledgerDb.transactions) do
        if item.from == target or item.to == target or canAdmin(actor) then
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
      net.respond(payload, getBalance(payload.data and payload.data.account_id, payload.data and payload.data.actor))
    end)

    context.on(events.global("net.request.currency.transfer"), function(event)
      local payload = event[2]
      local data = payload.data or {}
      net.respond(payload, transfer(data.actor, data.target_id, data.amount, data.reason))
    end)

    context.on(events.global("net.request.currency.accounts"), function(event)
      local payload = event[2]
      net.respond(payload, listAccounts(payload.data and payload.data.actor))
    end)

    context.on(events.global("net.request.currency.account.create"), function(event)
      local payload = event[2]
      local data = payload.data or {}
      net.respond(payload, createAccount(data.actor, data.account_id, data.name))
    end)

    context.on(events.global("net.request.currency.account.lock"), function(event)
      local payload = event[2]
      local data = payload.data or {}
      net.respond(payload, setLocked(data.actor, data.account_id, data.locked))
    end)

    context.on(events.global("net.request.currency.ledger"), function(event)
      local payload = event[2]
      local data = payload.data or {}
      net.respond(payload, getLedger(data.actor, data.account_id))
    end)

    context.log.info("currency service online")

    return {
      getBalance = getBalance,
      transfer = transfer,
      listAccounts = listAccounts,
      createAccount = createAccount,
      setLocked = setLocked,
      getLedger = getLedger,
    }
  end,
})

return service
