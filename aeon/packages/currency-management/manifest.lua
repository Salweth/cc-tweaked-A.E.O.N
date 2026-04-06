return {
  id = "currency-management",
  name = "Currency Management",
  version = "1.1.0",
  description = "Balance, transfers and account access",
  author = "AEON",
  issuer = "server-core",
  signature = "AEON-INTERNAL",
  target = {
    roles = { "workstation", "pocket", "server" }
  },
  permissions = {
    "currency.read",
    "currency.transfer",
  },
  files = {
    { from = "apps/currency.lua", to = "/aeon/apps/currency.lua" },
    { from = "bin/balance.lua", to = "/aeon/bin/balance.lua" },
    { from = "bin/transfer.lua", to = "/aeon/bin/transfer.lua" },
    { from = "bin/account.lua", to = "/aeon/bin/account.lua" },
    { from = "bin/ledger.lua", to = "/aeon/bin/ledger.lua" },
    { from = "services/svc_currency.lua", to = "/aeon/services/svc_currency.lua" },
    { from = "etc/currency.cfg", to = "/aeon/etc/currency.cfg" },
    { from = "lib/currency_api.lua", to = "/aeon/lib/currency_api.lua" },
  },
  entrypoints = {
    apps = { "currency" },
    commands = { "balance", "transfer", "account", "ledger" },
    services = { "svc_currency" },
  },
  dependencies = {
    services = { "svc_auth", "svc_net" },
    packages = {},
  },
}
