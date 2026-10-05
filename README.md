# AEON OS for CC:Tweaked

**A.E.O.N. — Advanced Ethics & Operations Network**

This workspace contains AEON OS, a modular event-driven operating environment for CC:Tweaked terminals, servers, and field devices.

Current runtime capabilities:
- event-driven kernel with cooperative tasks
- role-aware boot and startup app selection
- service lifecycle management
- central peripheral registry
- functional device capabilities with hot-plug discovery and isolated drivers
- shared character UI/theme for TERMINAL, CORE and compact FIELD surfaces
- kernel-managed foreground app launches with local surface auth continuity
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

### Pastebin bootstrap

Publish the contents of the small, standalone root `installer.lua` to Pastebin once.
It fetches the full profile installer from GitHub; no AEON files need to be copied
manually to the computer. HTTP must be enabled in CC:Tweaked.

```text
pastebin run <ID> workstation
pastebin run <ID> server
```

Without a profile it prompts, with `workstation` as the default. An optional second
argument selects a Git branch, for example `pastebin run <ID> server main`.
The same bootstrap can be started with
`wget run https://raw.githubusercontent.com/Salweth/cc-tweaked-A.E.O.N/main/installer.lua`.
`<ID>` is the ID of your Pastebin paste, not an ID shipped by this repository.
The direct workstation/server installers above remain supported.

```text
Pastebin -> installer.lua -> GitHub profile installer -> profile manifest -> AEON files
```

The server dashboard opens by default, and `Enter` opens the interactive admin shell.

## Update

Once AEON is installed:

```lua
update
```

`update` now uses the installer recorded in `/aeon/etc/update.cfg`, so a workstation stays on the workstation profile and a server stays on the server profile.

`update [branch]` fetches that installer and passes the selected branch, owner and
repository through to its manifest and file downloads. For older configurations
without a profile installer (or recording `installer.lua`), it chooses the recorded
profile, then falls back to the machine role. No interactive prompt is used by `update`.
After a successful install, `update.cfg` records the source and profile; additional
local fields are preserved. Reboot after updating to load the new runtime modules.

The manifests keep existing local configurations. Both installers preserve an
existing `role.cfg`; its default is written only on a fresh installation. Logs,
home files, package state and runtime data are not removed. The managed source
fields in `update.cfg` are intentionally updated. Installing another profile is
not an automatic role conversion: an existing role/configuration remains yours
to adjust. Downloads are applied one file at a time, so an interrupted update is
not transactional; rerun it to finish. Failure is reported rather than announcing
success, and source metadata is only written after all manifest files succeed.

## Devices and capabilities

Services use `context.devices`; apps receive `runtime.devices` and shell commands
receive `context.devices`. For example, in an app:

```lua
local speaker = runtime.devices.findCapability("speaker")
if speaker then
  local ok, accepted = speaker.call("playNote", "harp", 1, 12)
  if not ok then
    runtime.logger.warn(tostring(accepted))
  end
end
```

`call` returns `true, ...` with the adapter's return values, or `false, error`.
Thus `true, false` can be a valid peripheral response, not an exception.
An unavailable capability returns `nil`; `findAllCapabilities(name)` returns a list,
empty when none are present. `devices` in the AEON terminal lists peripherals and
their capabilities.

The initial drivers expose `modem`, `display`/`monitor`, and `speaker`. A monitor
demonstrates multiple capabilities on one device. They use the documented
[CC:Tweaked peripheral API](https://tweaked.cc/module/peripheral.html),
[modem](https://tweaked.cc/peripheral/modem.html),
[monitor](https://tweaked.cc/peripheral/monitor.html) and
[speaker](https://tweaked.cc/peripheral/speaker.html) methods.
No RFID, HUD, AE2 or other third-party API is assumed yet. Such capability queries
return `nil` until a driver with a verified adapter is added.

The physical registry is still available with its existing API. The device layer
rebuilds after every scan/refresh, including CC `peripheral` and `peripheral_detach`
events. It queues `aeon:devices.changed` through the existing event loop. Resolve
capabilities again after that event: all previous handles expire on a refresh,
including handles for unchanged peripherals. `net` does this automatically and
reopens its channels when a modem is attached or replaced, preferring wireless.
Driver loading, matching and binding failures are logged without stopping AEON.

See `ARCHITECTURE.md` for the driver contract and extension mechanism.

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
- server: `package list`, `package inspect disk`, `package write <id> disk`, `package install <id>`

`currency-management` now targets CCLC Trade Link operations instead of fake local accounts. It uses the Trade Link as the source of truth and keeps only an AEON audit log on the server.

## Architecture

Runtime contracts are documented in `ARCHITECTURE.md`.

This includes:
- task lifecycle
- service contract
- app contract
- global vs private AEON events

## Current Runtime

Distribution version `1.2.0` adds the AEON character interface and consistent app
launch/auth behavior on top of the device-capability layer.

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

## Interface and surfaces

The AEON theme uses off-white text on black, muted metadata, cyan headers/accents,
amber warnings, red errors and restrained green online labels. The core offers
shared components; each surface chooses its own layout:

- **TERMINAL**: hostname/role/identity/clearance header and a scrollable command
  region. Auth and network fields come from the running services. Type existing
  commands as before, or an installed app's name to launch it.
- **CORE**: server identity, modem availability, peers, live tasks, local sessions,
  uptime and service states. Enter opens the admin terminal; `exit` or Ctrl-T
  returns to CORE. R refreshes the dashboard. The server manifest includes the
  terminal app needed for this path.
- **FIELD**: Pocket hardware (or the `pocket` role) selects the compact FIELD header.
  Narrow/short and monochrome displays retain textual status meaning and input
  space. This is a compact terminal surface, not a separate field app/package.

New installations use `theme = "aeon"`. Kept existing configurations with the old
unused `theme = "amber"` also resolve to the AEON theme. Colours are centralized
in `aeon/core/theme.lua`; no hardware palette is changed. The new UI and theme
modules are present in all root manifests, including the legacy workstation list.

`drivers/display.lua` adapts CC terminal/monitor targets; `core/ui.lua` supplies
lightweight components and keyboard input. This keeps physical display handling
out of layouts. No desktop, mouse requirement or GPU dependency is introduced.
For example, a package app can draw a specialized surface using:

```lua
local define = dofile("/aeon/core/app.lua").define
return define({
  name = "operations",
  run = function(runtime)
    local ui = runtime.ui
    ui.clear()
    ui.header("OPERATIONS", runtime.hostname)
    -- Populate labels/status from the package's real service state.
    ui.wait("key")
  end,
})
```

All app entrypoints, including shell-launched package apps, now go through
`runtime.apps`. Each is a kernel task; the calling surface waits until it returns.
The foreground app owns the surface input, with terminal redirects preserved per
task. Existing CLI `print` output is redirected into the command region for
compatibility; the shell, CORE, login/clear and currency app use the UI API.

Login belongs to the owning surface's auth scope. Child apps on that surface see
the same username, roles and clearance; logout applies to all of them. Service
tasks and separate surfaces do not automatically inherit that login. Ending the
owning surface removes its session. `auth`, `whoami` and clearance checks retain
their APIs; the reported session `task_id` identifies the owner of the scope.

Optional packages may deploy drivers under `/aeon/drivers` and declare
`entrypoints.drivers` for boot-time registration. This supports future AE2,
Power Grid and BioForge surfaces without adding their business logic to the core.
The existing currency package provides an example of an app using the shared UI.
Its deployed app is updated by reinstalling the package after the OS update;
the updater refreshes the server's package source, not copies already installed
by the separate package workflow. The currency package now marks its config
`mode = "keep"`; reinstalls from disk or repository preserve the local config.

See `ARCHITECTURE.md` for the UI/backend contract, monitor capability adapters,
foreground lifecycle and authentication rules.

## Verification

Run `lua tests/run.lua` from the repository root with Lua 5.2 or newer. The suite
uses simulated CC APIs to check capabilities, failed drivers, detach/reattach,
network recovery, both installation profiles, update persistence, manifests and
boot from installed files only. It also checks keyboard editing/masking, monochrome
themes, resize, terminal isolation, shell/CORE return, app failure/cancellation,
auth continuity/revocation and installed package-driver activation. No test dependencies are installed on Minecraft
computers. In-game hardware and mod compatibility still require an in-game check.
