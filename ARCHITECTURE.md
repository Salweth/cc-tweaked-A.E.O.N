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
- `services`
- `config`
- `role`
- `hostname`
- `on(eventName, handler)`
- `emit(eventName, ...)`
- `emitPrivate(eventName, ...)`

Apps run as kernel-managed tasks. The shell is only an app.

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
- `mouse_click`
- `terminate`

## Logging Rules

- services log through their context logger, never by printing directly
- apps may print for UI, but should log lifecycle and failures
- infrastructure code should prefer structured AEON event names in log messages

## Dependency Rules

- apps do not call `peripheral.wrap(...)` directly
- apps resolve capabilities through services or the registry
- services may access drivers and the registry
- drivers are thin adapters, not policy layers
