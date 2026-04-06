local api = {}

local function loadConfig()
  if fs.exists("/aeon/etc/currency.cfg") then
    return dofile("/aeon/etc/currency.cfg")
  end

  return {
    server = nil,
  }
end

local function failure(code, message)
  return {
    ok = false,
    error = code,
    message = message,
  }
end

local function currentActor(runtime)
  local auth = runtime.services.get("auth")
  local session = auth and auth.current() or nil
  return session and session.username or nil
end

local function resolveTarget(runtime, net, cfg)
  local candidates = {}

  if cfg.server and cfg.server ~= "" then
    table.insert(candidates, cfg.server)
  end

  if net.config and net.config.server and net.config.server ~= "" then
    table.insert(candidates, net.config.server)
  end

  for _, nodeId in ipairs(candidates) do
    if net.getNode and net.getNode(nodeId) then
      return nodeId
    end
  end

  if net.listNodes then
    local nodes = net.listNodes()
    for _, node in ipairs(nodes) do
      if node.role == "server" then
        return node.id
      end
    end
  end

  return "*"
end

local function invokeRemote(runtime, action, data)
  local net = runtime.services.get("net")
  if not net then
    return failure("NETWORK_UNAVAILABLE", "Network service unavailable.")
  end

  local cfg = loadConfig()
  local target = resolveTarget(runtime, net, cfg)
  local ok, requestId = net.request(action, data or {}, target)
  if not ok then
    return failure("REQUEST_FAILED", tostring(requestId))
  end

  local waitOk, response = net.await(requestId, 5)
  if not waitOk then
    return failure("TIMEOUT", tostring(response))
  end

  if response.type == "error" then
    return failure("REMOTE_ERROR", response.data and response.data.message or "Remote request failed.")
  end

  return response.data or failure("EMPTY_RESPONSE", "No data returned.")
end

function api.balance(runtime)
  return invokeRemote(runtime, "currency.balance", {
    actor = currentActor(runtime),
  })
end

function api.transfer(runtime, targetId, amount, reason)
  return invokeRemote(runtime, "currency.transfer", {
    actor = currentActor(runtime),
    target_id = targetId,
    amount = amount,
    reason = reason,
  })
end

function api.accounts(runtime)
  return invokeRemote(runtime, "currency.accounts", {
    actor = currentActor(runtime),
  })
end

function api.ledger(runtime, targetId)
  return invokeRemote(runtime, "currency.ledger", {
    actor = currentActor(runtime),
    account_id = targetId,
  })
end

return api
