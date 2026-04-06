# AEON OS for CC:Tweaked

This workspace contains AEON OS, a modular event-driven operating environment for CC:Tweaked terminals, servers, and field devices.

Current runtime capabilities:
- event-driven kernel with cooperative tasks
- role-aware boot and startup app selection
- service lifecycle management
- central peripheral registry
- local auth sessions with clearance and role helpers
- task introspection service
- AEON multi-node discovery and request/response transport
- server-core dashboard and remote node handlers
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
