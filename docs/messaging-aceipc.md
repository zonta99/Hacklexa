# ACE IPC — `aceipc-daemon`

Static analysis of `/system/bin/aceipc-daemon` (doebrite, Fire OS 6.5.7.5 NS6575),
ARM 32-bit ELF, `sha256 050121eb…88ac`, decompiled with REA/Ghidra 12.2.

## Headline: ACE IPC is LIPC, carried forward

`aceipc-daemon` is a straight descendant of the 2nd-gen's **LIPC** `lipc-daemon`.
The binary still calls itself that: its log tags and help text read
`lipc-daemon received sigterm`, `lipc-daemon re-initializing...`,
`einit::lipc-daemon failed to init`, and the usage banner is

> lipc-daemon provides a way to execute programs on specified events / and a way
> to run programs to publish properties easily / Usage: lipc-daemon [-e
> <event-config-file>] [-p <property-config-file>] [-f]

So the on-device bus on Fire OS 6 is the **ACE** re-skin of Lab126 IPC, reached
through the `aceIpc_*` API in `libaceipc.so` (not LIPC's `liblipc`). The daemon is
internal version **1.3.0**.

## What the daemon is

A declarative **event/property → shell-command engine**. It owns no logic of its
own: two config files wire bus names to commands, and the daemon runs those
commands when the bus reads a property or delivers an event. The equivalent of
LIPC's `lipc-wait-event` / property bridges.

### CLI (`main` → `FUN_00012010`, getopt `"fe:p:v"`)

| Flag | Meaning |
|---|---|
| `-e <file>` | event-config file |
| `-p <file>` | property-config file |
| `-f` | foreground (do not `daemon(0,0)`) |
| `-v` | print `Version: 1.3.0` and exit |
| trailing arg | source namespace; default **`com.lab126.system`** |

`main` optionally parses an ACE user-config (`aceUserConfig_parser` →
`ace_initWithConfig`) before handing off. The source namespace becomes the
subscription key `<namespace>.event`. With neither `-e` nor `-p`, it just prints
usage. Signals: SIGINT/SIGTERM → clean shutdown, **SIGHUP → re-init** (`FUN_0001179c`).
Delivery runs on a dedicated pthread (256 KiB stack) draining a GLib async queue;
the main thread parks in `sleep(INT_MAX)`.

### Init / registration (`FUN_000117d4`)

`aceIpc_open(namespace)`, then parse the config files line by line (`#` comments,
whitespace-tokenised, 1 KiB line cap).

**Property config** (`-p`), three fields per line:

```
<property_name>  <access>  <command>
```

`<access>` selects the handler and type:

| access | type | handler(s) registered |
|---|---|---|
| `r`, `sr` | string get | `aceIpc_registerStringProperty` get @0x126a9 |
| `w`, `sw` | string set | set @0x1277d |
| `rw`, `srw` | string get+set | 0x126a9 + 0x1277d |
| `ir` | int get | `aceIpc_registerIntProperty` get @0x128bd |
| `iw` | int set | set @0x12971 |
| `irw` | int get+set | 0x128bd + 0x12971 |

On **get**, the daemon runs `<command>` and returns its stdout as the property
value (`Getting [%s]`, `popen`); on **set**, it runs `<command> <value>`
(`Setting [%s] to [%s]`, formatted `%s %s %s >/dev/null 2>/dev/null`). Logs each as
`Registered property [%s] with access [%s] with command [%s]`.

**Event config** (`-e`), three fields per line:

```
<event_name>  <publisher>  <command>
```

Entries are de-duplicated (name+publisher) into a GSList, then
`aceIpc_subscribeExt(ipc, publisher, event_name, handler@0x12451, 0)`. When the
event arrives, handler 0x12451 runs `<command>` (`Got event [%s] from publisher
[%s]` → `Handling event` / `Forwarding event`). A bare namespace subscription
(`aceIpc_subscribeExt(ipc, "<ns>.event", …)`) catches the rest.

## Security surface — resolved: no shell injection

Earlier this was flagged as a possible command-injection sink. **Decompiling the
executor (`FUN_00012b8c`) closes that: there is no shell.** The set handler
(`FUN_0001277c`, string-set @0x1277d) logs a `"%s %s %s"` string for readability,
but execution goes through `FUN_00012b8c(command, value)`, which:

1. `g_strsplit_set(command, " \t", 0)` — splits the **config-file command** into argv
   tokens,
2. **appends the bus-supplied `value` as the final argv element**, NUL-terminated,
3. `fork()`, redirects fds 0/1/2 to `/dev/null` (`FUN_00012cdc` = `dup2`), then
   **`execv(argv[0], argv)`** — no `/bin/sh`, no `system`, no `popen`.

So a writable (`w`/`iw`) property setter runs `command` with `value` as **one literal
argument**. Shell metacharacters in `value` (`;`, `|`, `` ` ``, `$()`) are inert —
the value never reaches a shell. The command itself comes from the trusted
property-config file, not the bus. **No command injection via the bus here.**

### get vs set — a deliberate asymmetry

The two paths handle the shell differently, and correctly:

| Path | Executor | Shell? | Untrusted input? |
|---|---|---|---|
| **set** (`w`/`iw`, `FUN_0001277c`→`FUN_00012b8c`) | `fork`+`execv`, value as last argv | **no** | yes (bus `value`) — but kept out of the shell |
| **get** (`r`/`ir`, `FUN_000126a8`→`FUN_00012ac4`) | **`popen(command,"r")`** (`/bin/sh -c`) | **yes** | **no** — get takes no caller value, only the config command |

So the path that takes untrusted bus input (`set`) avoids the shell entirely, and the
path that uses the shell (`get`) is fed only the trusted config command. Shell
metacharacters only ever matter in `command`, which an operator writes in the
property-config file. **Net: no bus-reachable command injection in `aceipc-daemon`.**
(A `get` command with a space is also split by the shell as normal — expected, since
`get` runs the command verbatim.) Compare against cgarrot's
network-surface findings before drawing conclusions.

## Imports of note

`aceIpc_*` (open, subscribeExt, sendEvent, createAndSendEventWithParameters,
register{Int,String}Property, add{Int,String}Param, get{Int,String}Param) from
`libaceipc.so`; `ace_init`/`ace_initWithConfig`/`aceUserConfig_parser` from the ACE
core; `aceLog_log` from `libace_log.so`; GLib/GThread for the queue. Built with
Android clang 3.8 (LLVM 3.8), gold linker.

## Next

- Decompile the four property handlers (0x126a9/0x1277d/0x128bd/0x12971) and the
  event handler (0x12451) to confirm the exact shell-exec and any escaping.
- `libaceipc.so` — the transport itself. **Done:** it is a **D-Bus** client; events
  are D-Bus signals, binary params ride inline as fixed byte arrays. See
  [transport-aceipc.md](transport-aceipc.md).
- Diff against the biscuit `liblipc` to measure what ACE changed.
