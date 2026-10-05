# AEON Runtime Contracts

This document defines the runtime contracts used by AEON OS.

## Task Lifecycle

Kernel tasks follow this lifecycle:

```text
ready -> running -> waiting -> running -> dead
ready -> error
waiting -> error
```

Rules:
- a task is a coroutine managed by `aeon/core/kernel.lua`
- a task must yield either `nil` or an event name string
- a yielded `nil` means "receive the next event"
- a yielded string means "wake me only for this event"
- a dead task is retained for inspection through `ps`
- an errored task is retained with status `error`
- invalid yields fail that task rather than crashing the scheduler
- nested emits are queued when a task or event dispatch is already running
- `aeon:task.finished(id, status, error)` is queued after completion or failure
- each task's terminal redirect is saved and restored through the display driver

## Service Contract

Services should be declared through `aeon/core/service_contract.lua`.

Required fields:
- `name`
- `start(context)`

Optional fields:
- `essential`
- `stop(context, instance)`

Service `start(context)` returns the service instance table exposed to apps and other services.

Service context provides:
- `runtime`
- `kernel`
- `logger`
- `registry`
- `devices`
- `ui`
- `services`
- `config`
- `role`
- `on(eventName, handler)`
- `emit(eventName, ...)`
- `emitPrivate(eventName, ...)`
- `log.debug/info/warn/error(...)`

Lifecycle:
1. registered
2. starting
3. running
4. stopped or failed

Global lifecycle events emitted by the service manager:
- `aeon:service.registered`
- `aeon:service.starting`
- `aeon:service.started`
- `aeon:service.stopped`
- `aeon:service.failed`

## App Contract

Apps should be declared through `aeon/core/app.lua`.

Required fields:
- `name`
- `run(context)`

Optional fields:
- `stop(context)`

App context provides:
- `runtime`
- `kernel`
- `logger`
- `registry`
- `devices`
- `ui`
- `apps`
- `services`
- `config`
- `role`
- `hostname`
- `on(eventName, handler)`
- `emit(eventName, ...)`
- `emitPrivate(eventName, ...)`

Apps run as kernel-managed tasks. The shell is only an app.

The launcher passes the runtime itself to `app.run(runtime)`;
the fields above describe the runtime facilities, with event subscriptions through
`runtime.kernel.on`. Service contexts provide the `on`/`emit` helpers directly.
Shell commands receive their own context with `runtime`, `registry`, `devices` and
`ui` (the scrollable command region).

### App launch and foreground ownership

Boot, the shell and CORE all use the same `runtime.apps` launcher from
`core/app.lua`:

```lua
local ok, err = runtime.apps.run(dofile("/aeon/apps/my_app.lua"))
```

`start(definition, options)` creates an app task and returns its ID.
`await(id)` waits for that task and returns `true` on return or `false, error` on
failure. `run` combines the two; it is called from a kernel task. `stop(runtime)`
is called once after the app returns or throws, including UI cancellation.
Existing `run(runtime)` modules remain valid without a new app framework.

Each app gets a shallow runtime context, sharing the same kernel, services,
registry and devices. It inherits the parent's UI backend/theme by default, with
its own view/event hook so callbacks do not leak between apps. `options.ui` and
`options.surface` select a different surface. Do not call another app's `run`
directly: the launcher owns task creation, terminal binding and auth scope.

The caller waits while a child owns the foreground of the same surface. Only
the foreground app receives events on that surface, so a suspended shell cannot
consume the child's keyboard or redraw over it. The scheduler snapshots task
count before resuming tasks: Enter that launches an app is not delivered to the
new app. On completion the previous foreground is restored, then the caller is
woken by the queued completion event. Services continue running normally.
Display-only backends do not consume keyboard input. This pass supplies one local
keyboard surface; routing keyboards or monitor touches across multiple interactive
hardware surfaces is left to their future input backends.

The shell opens apps by typing their name, preserves its command-region contents,
and resumes its prompt after exit or failure. On CORE, Enter opens the terminal as
a child app; `exit` or Ctrl-T returns to CORE. At the root terminal, Ctrl-T ends
that app as before. UI `wait` and `read` treat `terminate` as cancellation; legacy
apps using `os.pullEvent` retain their usual CC event behavior.

### Local authentication scope

Auth still exposes `login`, `logout`, `current`, role/clearance checks and
`listSessions`, including the optional explicit task ID. A root surface app owns
an `auth_scope` equal to its task ID. Child apps on that same surface inherit it.
Sessions are stored once by scope, with `task_id` identifying the owning root.
Looking up an explicit child task ID resolves its scope as well.

There is no copy of the credentials/session per app: login replaces the shared
identity and logout removes it for all apps in the scope. Returning from or
crashing a child keeps the parent's identity. When the owning surface task ends,
its session is removed. Background services and separately launched surfaces have
their own scopes and do not automatically inherit a user's identity. Username,
roles and clearance remain the existing authorization data; sessions remain local
and nonpersistent. No global computer-wide login is introduced.

## Event Model

AEON distinguishes two categories of internal events:

Global events:
- format: `aeon:<domain>.<action>`
- visible to every service/app that subscribes
- examples: `aeon:net.message`, `aeon:service.started`

Private events:
- format: `aeon:private:<scope>.<action>`
- still routed by the same kernel, but semantically reserved for one app or service family
- examples: `aeon:private:terminal.refresh`, `aeon:private:auth.prompt`

External ComputerCraft events remain unchanged:
- `modem_message`
- `peripheral`
- `peripheral_detach`
- `mouse_click`
- `terminate`

## Logging Rules

- services log through their context logger, never by printing directly
- apps may print for UI, but should log lifecycle and failures
- infrastructure code should prefer structured AEON event names in log messages

## Dependency Rules

- apps do not call `peripheral.wrap(...)` directly
- apps resolve capabilities through services or `runtime.devices`
- apps draw through `runtime.ui` and semantic theme roles
- services may access drivers and the registry
- drivers are thin adapters, not policy layers

## UI and surfaces

AEON means **Advanced Ethics & Operations Network**. Its character interface uses
a black background, off-white text, muted metadata, a restrained cyan accent,
amber warnings, red critical states and limited green online labels. It uses
ASCII separators so the CC character font does not need Unicode box drawing.
It does not modify the hardware palette.

Three small modules separate responsibilities:

- `drivers/display.lua`: adapts terminal-shaped CC targets, bounded regions and
  legacy stdout redirection; retains the old `bind` and capability-driver contract.
- `core/theme.lua`: supplies `text`, `muted`, `accent`, `success`, `warning`, `error`,
  `background`, `border`. `aeon` is the default; the previously unused `amber` value
  and unknown names fall back to it. Existing kept configs need no rewrite. A
  semantic palette table can override roles; monochrome targets use black/white.
- `core/ui.lua`: clipping, labels, status text, headers, separators, stream output
  and a compact keyboard line editor. It contains no peripheral discovery policy.

Bootstrap creates `runtime.ui` on the current terminal. Services receive that
same facility as `context.ui`; a service should not overwrite a foreground app's
surface. Background logs keep their persistent logger path. After UI initialization,
console log lines are buffered (latest 32) and drained by the shell between commands,
so a network/auth log cannot overwrite a password or command currently being edited.

Common UI methods (dot syntax):

| API | Behavior |
| --- | --- |
| `size()` | Current width and height |
| `clear()` | Clear with semantic background/text and reset cursor |
| `at(x, y, text, role, width)` | Clipped absolute text, preserving stream cursor |
| `separator(y)` | A thin ASCII separator |
| `header(surface, identity, rows)` | Up to three header rows; return first body row |
| `label(y, label, value, role)` | Responsive label/value columns |
| `status(y, label, state)` | ONLINE/OFFLINE/NOMINAL/WARNING/CRITICAL/RESTRICTED/LINKED |
| `print(...)`, `write(text, role)` | Stream text, wrapping/scrolling through the backend |
| `cursor(x, y)` | Set the stream cursor |
| `region(x, y, width, height)` | UI on a bounded scrolling region |
| `read({prompt=..., mask=...})` | Keyboard input, or `nil, error` on a display-only target |
| `wait(eventName)` | Wait for an event, handling cancellation; nil accepts any |
| `setEventHandler(handler)` | Per-view event hook while waiting/reading |
| `withTerminal(fn, ...)` | Compatibility boundary for existing CLI commands |

`read` supports typing, paste, cursor movement, Home/End, Delete/Backspace, masked
input and horizontal scrolling. Prompts may be functions so the current identity
is resolved when rendering. The shell hook relays auth/device state changes and
repositions its command region on resize without discarding the typed value.

Terminal and FIELD keep a large command region below a compact header. On tiny
screens header rows are dropped to preserve at least three input rows when
possible. CORE uses a distinct layout: actual modem availability, peer count,
live task count, session count, measured uptime and service lifecycle states.
It compresses metrics and reports omitted service rows on small displays.
`net` being ONLINE means the service is running, while NETWORK OFFLINE means no
active modem. No power/storage/BioForge measurements are fabricated.

Use a `region` below a header for long stream output; this protects it from
scrolling. The optional currency app follows that pattern as well. Boot marks
Pocket hardware as FIELD independently of the workstation/server install profile.

### Backend extension

`ui.create(backend, theme)` only needs the small character backend contract:
`size`, `isColor`, `cursor`, `position`, `blink`, `tone`, `clear`, `text`, `print`,
`write`, `withTerminal`, `region`, with `input` indicating keyboard support.
The CC implementation exposes `terminal` for scheduling legacy redirects and
`resize`, `visible`, `redraw` for its buffered regions. Region operations use the
documented [CC window API](https://tweaked.cc/module/window.html); the UI components
do not depend on it directly. A future renderer can provide the backend separately;
no DirectGPU dependency is present. A term-compatible surface can use the CC
adapter directly, with explicit input support.

For a monitor discovered through the device layer, pass a resolver so refreshes
can obtain a new capability handle:

```lua
local display = dofile("/aeon/drivers/display.lua")
local ui = dofile("/aeon/core/ui.lua")
local backend = display.fromCapability(function()
  local device = runtime.devices.get(monitorName)
  return device and device.capabilities.display
end) -- input defaults to false
local monitorUI = ui.create(backend, runtime.ui.theme)
monitorUI.header("STORAGE", runtime.hostname)
```

Absent/detached displays raise a local backend error that the app launcher isolates.
Use `devices.get(name)` to choose a configured monitor; apps never wrap it directly.
Supply `options.ui = monitorUI, options.surface = monitorName` when launching an
app on that surface. Use `start` for independent display-only apps rather than
blocking the local terminal with a modal `run`.

### Package-owned specialized surfaces

AE2, Power Grid and BioForge UI/business rules belong in optional packages.
Their apps reuse `runtime.ui` or create a different view/backend with the same
theme. Package manifests can target `/aeon/drivers/` as well as the existing app,
service, lib, bin and etc paths. Optional `entrypoints.drivers = { "bioforge" }`
loads `/aeon/drivers/bioforge.lua` at boot after package installation. Names are
simple module stems; malformed/missing drivers are logged and skipped. Their
declarations extend the existing device layer. Reboot activates newly installed
entrypoints, like the existing package services. This mechanism does not ship a
BioForge implementation or assume its peripheral API.

Package file entries may also declare `mode = "keep"` to seed a config only when
absent; unspecified mode still replaces code as before. Both disk/repository
install paths honor it. The currency config opts in so updating its UI does not
overwrite the machine's reader/ledger settings. Explicit package removal retains
the existing uninstall behavior.

## Device / Capability Layer

The separation is:

```text
CC peripheral API -> registry (physical snapshots)
                 -> devices + drivers (functional adapters)
                 -> services (policy) -> apps
```

`registry.list/get/find/findAll/refresh` retain their return shapes and primary-type
matching. Entries still have `name`, `type`, `methods`, `object`; the additive
`types` array records all types returned by CC:Tweaked. A peripheral disappearing
while being wrapped is skipped rather than crashing boot or refresh.

`registry.onRefresh(handler)` registers a synchronous internal observer called
after a complete scan, with `(reason, peripheralName)`. Observers must not yield
or recursively refresh. The single runtime device layer subscribes here, so a
direct `registry.scan()` or `registry.refresh()` cannot leave capabilities stale.
The registry remains independent of any driver modules.

Bootstrap creates `runtime.devices` once using `devices.create(registry, options)`.
Services receive the same instance as `context.devices`; do not `dofile` the core
module to obtain a separate device inventory.

Device-layer API:

| Function | Result |
| --- | --- |
| `list()` | Physical devices with their declared capability maps |
| `get(name)` | Logical device, or `nil` |
| `findCapability(name)` | First provider in registry type/name order, or `nil` |
| `findAllCapabilities(name)` | List of all providers for that capability |
| `refresh()` | Refresh the physical registry and return the rebuilt device list |
| `registerDriver(definition)` | `true`, or `false, error`; refresh to apply |

Logical devices have `{ name, type, capabilities }`. Each capability maps to a
provider with `{ name, type, driver, capability, call }`. Treat returned descriptors
as read-only. `provider.call(method, ...)` uses dot syntax and returns the `pcall`
contract: `true, ...` including nil/false/multiple values, or `false, error`.
Unknown methods, expired handles and peripheral exceptions fail locally.
Adapters are not exposed as raw peripheral objects to apps.

Each scan invalidates all old providers, even for unchanged names. A detached
device later using the same name cannot revive an old handle. Acquire a fresh
provider after `aeon:devices.changed` or immediately before use. Services retain
responsibility for retry/backoff, permissions, resource ownership and device choice.

### Driver contract

Drivers are explicitly loaded in configured order; there is no directory crawler
or new service manager. A module returns:

```lua
return {
  id = "example.text_output",
  match = function(entry, helpers)
    return helpers.hasMethods(entry, { "write" })
  end,
  bindCapabilities = function(entry)
    return { text_output = { write = entry.object.write } }
  end,
}
```

`match(entry, helpers)` uses physical metadata. Helpers provide
`hasType(entry, type)` (including secondary types) and
`hasMethods(entry, requiredNames)` (metadata and callable-object checks).
`bindCapabilities(entry)` returns `{ [capabilityName] = adapterTable }` with methods
whose names/semantics form the capability contract. Multiple capabilities and
multiple matching drivers are allowed. The first driver declaring the same
capability on the same physical device wins; collisions are logged.

Loading, matching, binding and capability-table validation are isolated with
`pcall`; one bad driver does not discard other devices or capabilities. Matching
and binding must be quick, must not yield, and must not open channels or acquire
resources: rebuilding may happen repeatedly. Put lifecycle work and policy in
services, and put method-name/argument adaptation in drivers.

The built-in modules are `modem.lua`, `display.lua`, `speaker.lua`. They declare
`modem`, `display` and `monitor`, and `speaker`, respectively. Their adapters use
the corresponding CC APIs. The existing `modem.detect/isWireless` and
`display.bind` helpers remain compatible. `currency.lua` remains the existing
CCLC scaffold and does not claim generic RFID support.

To extend the boot-time set, set `device_drivers` in `/aeon/etc/aeon.cfg` to an
ordered list of absolute driver paths. This replaces the default list, so include
the built-ins when they are still needed. Add every distributed driver and helper
to the relevant root manifests. Runtime code can alternatively register a driver
then call `runtime.devices.refresh()`; registrations are not persisted automatically.
Unknown mod integrations remain unimplemented until their APIs and capability
contracts have been verified.

### Hot-plug and events

`svc_registry` handles CC `peripheral` / `peripheral_detach`, refreshing physical
and logical state synchronously. The layer queues
`aeon:devices.changed(reason, name, generation)` after each rebuild; `name` is nil
for manual/initial scans. The existing `aeon:registry.changed(reason, name)` event
remains available for attach/detach. Both notifications use `os.queueEvent`, so
the existing kernel dispatches them on its normal loop rather than recursively
resuming a task that initiated a refresh. Notifications describe a refresh, not
a historical snapshot: query the current inventory when handling them.

`svc_net` consumes `modem` capabilities, selects a working wireless candidate
before the wired fallback, opens its channels, and repeats selection after device
changes. A missing/failed modem leaves the service online and send operations
return `false, error`. Its existing public `modem` registry entry and `isWireless`
status fields are updated together. Announced network service capabilities
(`auth`, `tasks`, etc.) are distinct from local hardware capabilities.

## Installation and update contract

`installer.lua` is the standalone Pastebin bootstrap: select/prompt for a profile,
fetch the full `installer-workstation.lua` or `installer-server.lua` from GitHub,
then execute it with the selected branch. It requires no installed AEON modules.
The full installers remain independently runnable and select their respective
manifests. `manifest.lua` remains the legacy workstation file list. All three
root manifests distribute the device layer and built-in drivers.

```text
installation -> /aeon/etc/update.cfg -> update [branch]
             -> GitHub profile installer -> profile manifest -> files
```

`update.cfg` records `owner`, `repo`, `branch`, `installer`, `profile`. `update`
passes source overrides to the installer so all fetches use the same source.
Legacy/missing installer selection falls back to the stored profile or role.
The installer merges managed fields after file installation, preserving extra
local fields; `role.cfg` is created only when absent. A reinstall does not silently
convert an existing machine role.

Manifest entries with `mode = "keep"` seed configuration on first install only.
No updater pruning is performed: logs, `/aeon/var`, `/aeon/home`, installed package
data and files outside the manifest remain in place. The server's package-source
currency configuration is also kept. Runtime package installation/removal remains
the separate existing package workflow.

Installers reject an invalid/empty/wrong-profile manifest and stop on download or
write errors. Files are updated sequentially, not as an atomic transaction; a
failed update may have replaced earlier code files. Rerun the installer/update
and reboot after success. No automatic reboot or configuration deletion occurs.
