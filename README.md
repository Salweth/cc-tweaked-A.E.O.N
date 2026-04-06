# AEON OS for CC:Tweaked

This workspace contains the initial AEON OS scaffold for a CC:Tweaked setup.

Current V1 goals:
- bootstrapping
- role-aware startup
- logging
- peripheral registry
- minimal shell

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
