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

From a CC:Tweaked computer with HTTP enabled:

```lua
wget run https://raw.githubusercontent.com/Salweth/cc-tweaked-A.E.O.N/main/installer.lua
```

If you prefer Pastebin, upload `installer.lua` there and run the pasted script. The installer then fetches the manifest and the remaining files directly from GitHub.

## Update

Once AEON is installed:

```lua
update
```

This downloads the latest `installer.lua`, applies the manifest, and preserves local config files in `/aeon/etc` by default.

## Architecture

Runtime contracts are documented in `ARCHITECTURE.md`.

This includes:
- task lifecycle
- service contract
- app contract
- global vs private AEON events

## Current Runtime

Version `0.5.x` focuses on solidifying the system layer before business features.

Main services currently available:
- `log`
- `registry`
- `auth`
- `tasks`
- `net`

Server-oriented commands available:
- `net`
- `node`
- `send`
- `ping`
