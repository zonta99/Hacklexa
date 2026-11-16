# Alexa Hybrid Execution (AHE) — the on-device Alexa engine

The Alexa stack on `doebrite` (Fire OS 6.5.7.5) is **Alexa Hybrid Execution**, a
local+cloud engine built on the open-source **AVS Device SDK**. This is the biggest
departure from the 2nd-gen `biscuit`, which had only the `alexad` cloud proxy and no
on-device understanding. Evidence here is from shipped config (`/system/etc/`), the
version file, and the ELF exports of `libAlexa.so` (REA, no cloud contact).

## Engine identity

`/system/etc/ahe.version` → **`AlexaHybridLitespeed-1.0.18844.0`**. The controller
binary is `/system/bin/AlexaHybridExecutionControllerLitespeed` (10 MB, ARM 32-bit).
Model class is **`odie-litespeed`** — "Litespeed" is Amazon's compact on-device NLU
line. DAC component id `AHELiteSpeed`, `DacService.UUID 132`.

## Component map (`ahe.config.json`)

| Component | Role | Key config |
|---|---|---|
| **CoreEngine** | the NLU/ASR engine | workingDir `/data/alexahybrid/files/CoreEngineWorking`; wake word via `pryon1LibraryPath = /system/lib/libpryon.so` |
| **ExecutionController (EC)** | request execution front door | binds **`0.0.0.0:7802`** + Unix sockets in `/data/alexahybrid/ec-sockets`, `SocketPermissions: ALL`, `StartLSF: false` |
| **LocalRequestOrchestrator (LRO)** | routes each utterance local vs cloud | sockets `/data/alexahybrid/lro-sockets`; **`CloudInteractionSamplingRate: 0.01`** (1% sampled to cloud); **ClearPolicy** at `/system/etc/ahe.clear.policy.js`, `UseClearPolicy: true` |
| **ArtifactManager (AM)** | downloads NLU models | DAVS client, `DavsPollServer.TcpPort 9091`, model dir `/data/alexahybrid/files/AmModel`, `DownloaderPolicy: MIN_STORAGE_FOOTPRINT` |
| **HybridPlatformInterface** | app-facing backend | `Backend: HR` (HybridRouter) |
| **PlatformServices / SettingsManager** | device services, settings | `ps-sockets`, settings persisted to `files/sm` |
| **Metrics** | telemetry | `MetricsLoggerType: ACE_METRICS` → the ACE metric bus |

The **HybridRouter** (`hybrid_router_config.json`) points the platform at
`tcp localhost:7802` — the EC. So the flow is: app → HybridRouter → EC:7802 → LRO
decides local vs cloud → CoreEngine (local) or AVS (cloud).

### Note: EC binds all interfaces

`ExecutionController.Address = 0.0.0.0` with `SocketPermissions: ALL` means the TCP
control port 7802 is not loopback-pinned in config, even though the router uses
`localhost`. Whether the listener is firewalled or auth-gated at runtime is the next
thing to verify in the controller binary — cross-check cgarrot's network-surface
map (ports 4070/8888/…); 7802 and the DAVS poll port 9091 are new data points.

## Built-in local skills (`builtInSkillCollections`)

Handled on-device, no cloud round trip:

- **SmartHome** (`amzn1.ask.skill.d3a1dfa8-…`) — local appliance driver registry
  (`/system/etc/smartHomeSkill/driverRegistry.db`) and a customer-home-registry DB;
  action interfaces `SmartHome.executeAction` / `executeActionClassic`.
- **Alerts** (`com.amazon.alexahybrid.AlertsSkill`) — timers/alarms.
- **StopFallback** (`…StopFallbackSkill`) — the "stop" catch-all.
- **Snooze** (`BuiltInSnoozeSkill: true`).

So "set a timer", "stop", and local smart-home control work without the cloud; the
LRO only reaches AVS for what the ClearPolicy marks cloud-only (and the 1% sample).

## `libAlexa.so` — the AVS Device SDK surface

114 KB, ARM 32-bit, **201 ELF exports**, all in the open-source
`alexaClientSDK::capabilityAgents::alexa` namespace — i.e. a device build of the
public **AVS Device SDK**, not bespoke Amazon code. Recovered classes:

- `AlexaInterfaceMessageSender` — sends Alexa-interface events (state reports,
  change reports, deferred/error responses) to AVS.
- `AlexaInterfaceCapabilityAgent` — handles `Alexa.*` directives (pre-handle,
  handle, cancel, exception).
- `AlexaEventProcessedNotifier` — the `Alexa.EventProcessed` notifier.
- `createDefaultAlexaInterfaceCapabilityAgent(...)` takes a
  `multiAgentInterface::AgentManagerInterface` — **multi-agent capable** (Alexa
  alongside other voice agents).

Because this layer is upstream AVS Device SDK, the novel device-specific logic is in
the **Litespeed controller** and the **CoreEngine**, not here. `libAlexa.so` is the
seam between Amazon's shipped engine and the open SDK.

## AVS endpoints (from config, not contacted)

- Cloud: `avs-alexa-14-na.amazon.com` (`AlexaClientSDKConfig.json → acl.endpoint`).
- CSM proxy map (`alexa_endpoint_host_names.json`): prod `latinum.amazon.com`,
  gamma `polaron`, preprod `tetryon`, per region (NA/EU/FE/CN).
- Local state DBs under `/data/avs/resources/` (alerts, bluetooth, settings, …).

## Controller internals (static, from the 10 MB binary)

Decompiled symbols in `AlexaHybridExecutionControllerLitespeed`
(`sha256 d51dfd61…8afd`) put the network stack in
`AlexaHybridSDK::ExecutionController::Net`:

- **`Net::Server::TLSServer`** — the EC front door is a **TLS server**, not a plain
  socket. It also runs a daily-metrics timer. So traffic to port 7802 is TLS-wrapped.
- **`Net::BaseConnection`** — per-connection read/write/close/stop state machine,
  driven by the SDK's `Common::Executor` (`scheduleRead`,
  `onProtocolHandlerReadyToWrite`).
- **`Net::Http2::AvsStreamAdapter`** — HTTP/2 adapter bridging to AVS
  (`sendResponseAudio`), i.e. the cloud leg.
- **`Core::CoreConnection` / `ConnectionManager` / `ExecutionControllerFacadeImpl`** —
  message routing: `sendMessageToChannel`, `sendMessageToDownChannel`,
  `sendMessageToChannelControllerManager`,
  `sendMessageToDownchannelForDivergence`, plus update handlers
  (`handleExecutionPolicyUpdated`, `handleInterfaceConfigArtifactUpdated`,
  `handleLroReadinessUpdated`, `handleLocalEngineStateSluUpdated`,
  `notifyLocalEngineIsReady`).

### The external-listen gate (not yet resolved)

The binary reads two config keys the shipped JSON does **not** set:

- `AlexaHybrid.SDK.ExecutionController.ListenOnExternalEndpoint`
- `AlexaHybrid.SDK.ExecutionController.ListenOnExternalUnsecureEndpoint`

Shipped `ahe.config.json` sets only `Address=0.0.0.0`, `Port=7802`, `StartLSF=false`,
leaving both `ListenOnExternal*` flags at their **binary defaults**. So `0.0.0.0` is
the configured bind template, but whether the EC actually opens a non-loopback
socket — and whether an *unsecure* (non-TLS) external endpoint is ever allowed — is
decided by those two defaults. The key is read through a 64-byte config-key accessor
(`FUN_0046b348` → the key string at `0x26e378`); the value is consumed deep in the
templated config/Net setup, too many hops to pin statically here without high effort.

**Honest status:** the EC is TLS-fronted and has an explicit external-listen gate,
which is the safe design. Whether port 7802 is reachable off-device on this build is
**not proven** from static config alone — the default of `ListenOnExternalEndpoint`
decides it. Best answered on a live device (an `ss -ltnp` / nmap of 7802, the way
cgarrot measured the network surface), or by tracing the config consumer in a
follow-up session. Do not state it as exposed or as loopback-only until then.

## Open threads

- `ahe.clear.policy.js` is referenced but **not shipped** in the OTA `/system/etc`
  — likely delivered at runtime by ArtifactManager/DAVS or generated by the engine.
  Its logic (what stays local) is the interesting policy surface to recover live.
- Confirm the EC `0.0.0.0:7802` bind and its wire protocol in the controller binary.
- Map CoreEngine ↔ `libpryon.so` (wake word) and the `odie-litespeed` model format.
