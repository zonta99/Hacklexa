# Findings

First-pass static survey of the extracted `doebrite` `/system` (Fire OS 6.5.7.5,
NS6575). Decompilation with REA is the next phase; this records the architecture
map that frames it.

## The headline: not `alexad`

The `biscuit` (2nd gen) stack is a C++ daemon `alexad` + `libalexad.so` talking the
AVS cloud over SPDY, with an on-device **LIPC** bus. **`doebrite` has none of that.**
There is no `alexad` binary. Instead:

| Layer | `biscuit` (2nd gen) | `doebrite` (3rd gen clock) |
|---|---|---|
| OS | Fire OS 5.5 / Android 5.1.1 | Fire OS 6.5.7.5 / Android 7.1.2 |
| SoC | MT8163 | MT8167 |
| Userland | 32-bit | 32-bit (`armeabi-v7a`, EABI5) |
| Alexa engine | `alexad` + `libalexad.so` | **`AlexaHybridExecutionControllerLitespeed`** (10.6 MB) + `libAlexa.so` |
| SDK | custom Doppler | **Alexa Client SDK** (`libacsdk*`, `AlexaClientSDKConfig.json`) |
| On-device IPC | LIPC (Lab126 IPC) | **ACE IPC** (`aceipc-daemon`, `aceipc-send-event`, …) |
| Platform framework | liblab126utils | **ACE** (`ace`, `ace_*d` daemons: power, thermal, sensors, metric, OTA) |

So `doebrite` runs the modern **AVS Device SDK + Alexa Hybrid Execution (AHE)** —
local/offline intent handling alongside the cloud — on top of Amazon's **ACE**
embedded platform layer. This is a genuinely different device from what
`kilworks/echo-dot-rea` documented, and nobody has decompiled this stack yet.

## Components worth analysis

- **`AlexaHybridExecutionControllerLitespeed`** — the Alexa engine, the big binary.
  "Litespeed" + "Hybrid Execution" points at on-device inference/routing.
- **`libAlexa.so`, `libacsdk*` (57 libs)** — the Alexa Client SDK surface.
  **Done:** AHE architecture mapped — AlexaHybridLitespeed engine, EC/LRO/CoreEngine/
  ArtifactManager components, built-in local skills, libAlexa.so = AVS Device SDK
  build. See [alexa-hybrid-ahe.md](alexa-hybrid-ahe.md).
- **ACE IPC** — `aceipc-daemon` and the `aceipc-*` CLIs: the on-device message bus
  (the LIPC equivalent). The transport to map first.
  **Done:** `aceipc-daemon` decompiled — it is LIPC's `lipc-daemon` carried forward,
  a config-driven event/property→shell-command engine. See
  [messaging-aceipc.md](messaging-aceipc.md).
  Transport is D-Bus; see [transport-aceipc.md](transport-aceipc.md).
- **`ace_*` daemons** — `ace_powerd`, `ace_thermald`, `ace_sensorsd`,
  `ace_metric_daemon`, `ace_otad`, `acebuttond`, `aceinputmanager`. The HAL layer.
- **`amzn_dha_tool` / `fireos-dha` / `libacehal_dha.so`** — device health attestation
  (same family as `biscuit`, worth diffing).
- **`libpryon.so` / `libPryonDetector.so` / `libpryonlite.so`** — wake-word engine.
- **`mixer` / `libmixerAPI.so`** — audio mixer (matches `echo-dot-assist`'s notes).
- **`AceCredentialManagerService`** — credential/identity service.

## Boot chain (not yet analyzed)

`lk.img` (232 KB), `tee1.img`/`tee2.img` (2.3 MB each), `boot.img` (9.5 MB),
`brhgptpl_0..3.img` partition tables — all dumped, pending REA. `cgarrot` already
disassembled `lk` for `doebrite`; cross-check rather than redo.

## Next

1. Install REA (`npx rea-agents setup`), register with this agent.
2. Decompile `aceipc-daemon` first (the bus), then
   `AlexaHybridExecutionControllerLitespeed` + `libAlexa.so`.
3. Document each subsystem the way `biscuit` is documented, with evidence.
