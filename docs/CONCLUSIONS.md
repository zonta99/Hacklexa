# Conclusions — the turning point

After mapping the `doebrite` (Echo Dot 3 w/ clock, Fire OS 6.5.7.5) stack statically
from the OTA, the project reached a clear inflection point. Stating it plainly so the
effort points the right way.

## What we proved

Six subsystems documented, every claim backed by shipped bytes (REA/Ghidra 12.2) or
shipped config — no device contact:

1. **Extraction** works and is reproducible — `payload.bin` → `payload_dumper` →
   `unsquashfs` (zstd). The exact on-device build. ([extraction.md](extraction.md))
2. **ACE IPC = LIPC carried forward** — `aceipc-daemon` is still `lipc-daemon`, a
   config-driven event/property→command engine. ([messaging-aceipc.md](messaging-aceipc.md))
3. **Transport = D-Bus** — `libaceipc.so` drives libdbus directly; attachments moved
   from biscuit's shared-memory queues to inline byte arrays. ([transport-aceipc.md](transport-aceipc.md))
4. **Alexa = Hybrid Execution (Litespeed)** — a local+cloud engine on the open AVS
   Device SDK, a whole architecture biscuit never had. ([alexa-hybrid-ahe.md](alexa-hybrid-ahe.md))
5. **Attestation = DHAv2** — DAK + CSR + signed cert chain over a Binder/AIDL service,
   stronger than biscuit's DHAv1. ([attestation-dha.md](attestation-dha.md))
6. **Controller 7802** — a TLS server gated by `ListenOnExternalEndpoint`.

## The turning point: no static software foothold

The three most promising static attack surfaces were each probed and each came back
**clean or hardened**:

- **`aceipc-daemon` shell-exec** — untrusted bus input never reaches a shell: `set`
  uses `execv` with the value as a bounded argv arg; `get` uses `popen` but only on
  the trusted config command. **No bus command injection.**
- **`libaceipc.so` message parsing** — `getCharArrayParam` borrows the libdbus buffer
  via `get_fixed_array` (pointer+length), no fixed-buffer copy. **No overflow.**
- **DHAv2 attestation** — TEE-held DAK signing a cert chain; *stronger* than biscuit,
  and the reason a cloned/tampered device fails. **Not a weakness.**

Combined with what the public record already establishes for this exact device —
cgarrot's [doebrite research](https://github.com/cgarrot/echo-dot-3-doebrite-research)
proves the boot chain is cryptographic end-to-end and **no custom firmware can be
installed OTA**, and `Gamer92000/echo-dot-assist` lists `doebrite` as **no known
exploit** (the only unlock is a hardware teardown on `donut`, and recent units can be
bricked by it) — the honest conclusion is:

> **`doebrite` is a hardened, modern device with no software-only foothold. The value
> of this work is the architecture map, not an exploit. The only remaining attack
> surface is dynamic — the network/BLE OOBE setup path — which needs a live device
> and is already cgarrot's territory.**

## Where to take it

- **Contribute the architecture, not an exploit.** This repo's six subsystem docs are
  the thing `kilworks/echo-dot-rea` doesn't have for the 3rd-gen clock. Open an issue
  there offering `doebrite` as a documented target (don't duplicate cgarrot).
- **If you want a real foothold, it is dynamic, not static.** The lead is the
  OOBE/WhisperJoin WiFi-credential path — a consumer that copies the `(ptr,len)` blob
  `libaceipc` hands it. That needs a live device on an isolated network, which your
  unit (not rootable, must stay offline to avoid updates) makes impractical and risky.
- **Do not put the device online with Amazon** — an update can close whatever the
  community later finds, and recent `donut` units have bricked on unlock.

Static analysis from the OTA has given what it can give here. That is the turning
point: the project's deliverable is documentation of a well-secured device.
