# AEON OS for CC:Tweaked

This workspace contains AEON OS, a modular event-driven operating environment for CC:Tweaked terminals, servers, and field devices.

Current runtime capabilities:
- event-driven kernel with cooperative tasks
- role-aware boot and startup app selection
- service lifecycle management
- central peripheral registry
- local auth sessions with clearance and role helpers
- task introspection service
- AEON multi-node discovery and request/response transport over wireless modems
- server-core dashboard and remote node handlers
- currency peripheral driver scaffold with CCLC card reader compatibility
- install/update workflow via GitHub raw files

Target in-game layout:

```text
/aeon
  /boot
  /core
  /drivers
  /services
  /shell
  /bin
  /apps
  /lib
  /etc
  /var
  /home
```

## Install

From a CC:Tweaked workstation with HTTP enabled:

```lua
wget run https://raw.githubusercontent.com/Salweth/cc-tweaked-A.E.O.N/main/installer-workstation.lua
```

From a dedicated AEON server node:

```lua
wget run https://raw.githubusercontent.com/Salweth/cc-tweaked-A.E.O.N/main/installer-server.lua
```

The legacy `installer.lua` now forwards to the workstation installer.
The server dashboard opens by default, and `Enter` opens the interactive admin shell.

## Update

Once AEON is installed:

```lua
update
```

`update` now uses the installer recorded in `/aeon/etc/update.cfg`, so a workstation stays on the workstation profile and a server stays on the server profile.

AEON networking is designed around wireless or ender modems. Wired modems expose shared cable peripherals, which is not a valid topology for isolated AEON nodes.

Recommended network config shape:

```lua
return {
  directory_channel = 42,
  node_channel = 1042,
  reply_channel = 1042,
  server = "server-core",
  address_book = {
    ["server-core"] = 1042,
  },
}
```

Use one shared `directory_channel` for discovery, and one dedicated `node_channel` per machine for direct traffic.

## Packages

AEON distinguishes between an app and a package:
- an app is a functional module
- a package is a distribution unit

Server nodes can host package sources under `/aeon/packages/`.
Workstations can install optional packages from floppy disks using `app install disk`.

Current V1 commands:
- workstation: `app list`, `app info <id>`, `app install disk`, `app remove <id>`
- server: `package list`, `package inspect disk`, `package write <id> disk`

`currency-management` now targets CCLC Trade Link operations instead of fake local accounts. It uses the Trade Link as the source of truth and keeps only an AEON audit log on the server.

## Architecture

Runtime contracts are documented in `ARCHITECTURE.md`.

This includes:
- task lifecycle
- service contract
- app contract
- global vs private AEON events

## Current Runtime

Version `0.6.x` focuses on locking the runtime and introducing the first dedicated server-core profile.

Main services currently available:
- `log`
- `registry`
- `auth`
- `tasks`
- `net`
- `server` (server role only)

Server-oriented commands available:
- `net`
- `node`
- `send`
- `ping`

Workstation terminal commands include:
- `cat`
- `edit`
- `ls`
- `login`
- `logout`
- `auth`

## Server Role

Set `/aeon/etc/role.cfg` to:

```lua
return {
  role = "server"
}
```

With the default config, a server node boots into the passive `server` app while workstations keep the interactive `terminal` app.
