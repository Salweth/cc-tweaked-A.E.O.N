# AEON Runtime Contracts

This document defines the runtime contracts used by AEON OS.

## Task Lifecycle

Kernel tasks follow this lifecycle:

```text
ready -> waiting -> dead
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
- `services`
- `config`
- `role`
- `hostname`
- `on(eventName, handler)`
- `emit(eventName, ...)`
- `emitPrivate(eventName, ...)`

Apps run as kernel-managed tasks. The shell is only an app.

The existing implementation passes the runtime itself to `app.run(runtime)`;
the fields above describe the runtime facilities, with event subscriptions through
`runtime.kernel.on`. Service contexts provide the `on`/`emit` helpers directly.
Shell commands receive their own context with `runtime`, `registry` and `devices`.

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
- services may access drivers and the registry
- drivers are thin adapters, not policy layers

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
