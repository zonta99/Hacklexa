# ACE IPC transport — `libaceipc.so`

What carries the ACE IPC bus that [`aceipc-daemon`](messaging-aceipc.md) and the ACE
daemons speak. `/system/lib/libaceipc.so`, 50 KB, ARM 32-bit. Evidence from its
dynamic imports and string table (REA + `strings`/`nm`), no device contact.

## Headline: ACE IPC is a D-Bus client

`libaceipc.so` is **NEEDED-linked against `libdbus.so`** and drives the full
libdbus API directly — not a bespoke socket, not shared memory. So the Fire OS 6
on-device bus is **D-Bus**, the same substrate Lab126's LIPC always used (the device
still ships `liblipc.so` / `liblipcprop.so`, and this library logs
`LIPC opened with service name: [%s]`). `aceIpc_*` is a thin C veneer over D-Bus.

Imported libdbus calls include `dbus_bus_get_private`, `dbus_bus_request_name`,
`dbus_bus_add_match`/`remove_match`, `dbus_connection_send`,
`dbus_connection_pop_message`, `dbus_connection_read_write`,
`dbus_connection_set_watch_functions`, and the `dbus_message_iter_append_basic` /
`append_fixed_array` / `get_basic` family.

## Wire model

- **Connection**: a *private* bus connection (`dbus_bus_get_private`), its name
  claimed with `dbus_bus_request_name` (→ `aceIpc_errDuplicateServiceName`).
  `aceIpc_open` / `openEx` / `openNoName` are the entry points; the name is the
  "service name" the daemon registers (e.g. `com.lab126.system`).
- **Events = D-Bus signals.** `aceIpc_subscribeExt` installs a match rule, formatted
  verbatim as `type='signal',interface='%s'` plus `,member='%s'` — i.e. **interface =
  publisher/service, member = event name**. The listen thread
  (`aceIpc_prvListenThread`) pops messages and dispatches through
  `aceIpc_processSignal` / `processMethod` / `processReply`.
- **Parameters**: `addIntParam` / `addStringParam` / `addCharArrayParam`, read back
  with the matching `get…Param`. Ints and strings go through
  `dbus_message_iter_append_basic`; **binary blobs go through
  `dbus_message_iter_append_fixed_array`** ("Adding charArray param … size: %d").
  This is the big change from `biscuit`'s LIPC, which carried attachments in
  **shared-memory queues** — on `doebrite` the payload rides **inside** the D-Bus
  message as a fixed byte array.
- **Properties**: `register{Int,String,CharArray}Property`, `get/set…Property`,
  `setThenGetCharArrayProperty`, `accessPropertyAsync`, with a configurable
  property-access timeout (`getPropAccessTimeout`). These are D-Bus method
  call/reply exchanges.

## Event-loop integration

D-Bus watches are folded into a classic `select()` loop:
`aceIpc_prepareFdSetsFromWatches` + `prvDbusAddWatch` / `prvDBusRemoveWatch` /
`prvDBusWatchToggled`, woken by a **self-pipe** (`aceIpc_spipInit` / `spipSignal` /
`spipClearSignal` / `spipGetWaitFd`) so a send on one thread can interrupt the listen
thread. The shared connection is serialized with a mutex:
`aceIpc_prvLockBus` / `prvReleaseBus` / `ensureBusReadyForWrite`.

## A WiFi-credential property surface

`libaceipc.so` carries a dedicated validation vocabulary for **WiFi credentials**
flowing as properties: `aceIpc_invalidSSIDLength`, `invalidWEPPSKLength`,
`invalidWPAWPA2PSKLength`, `invalidHexKey`, `unsupportedSecurityType`,
`noPSKFoundWhenSecured` / `foundPSKWhenNotSecured`,
`noSMethodFoundWhenSecured` / `foundSMethodWhenNotSecured`, `invalidSecuredValue`,
`invalidHiddenValue`. So network-setup credentials are set/validated over this bus —
the plumbing behind device onboarding (cross-reference cgarrot's OOBE / WhisperJoin
work on the same device). Worth a focused look at how a `CharArray` PSK property is
validated and where it is stored.

## Lineage, summarized

```
biscuit (2nd gen)   LIPC  → D-Bus, attachments in shared-memory queues
doebrite (3rd gen)  ACE IPC (aceIpc_* over libaceipc.so) → D-Bus,
                    attachments inline as fixed byte arrays
```

Same D-Bus substrate, a cleaner C API, and the attachment transport moved off
shared memory and into the message itself.

## Next

- Decompile `aceIpc_subscribeExt` and `prvListenThread` to confirm the exact match
  string and dispatch, and `aceIpc_setCharArrayProperty` for the WiFi-credential
  validation/storage path.
- Identify which D-Bus daemon/bus address is used (not a literal in this library —
  likely from the environment / Android's dbus-daemon).
