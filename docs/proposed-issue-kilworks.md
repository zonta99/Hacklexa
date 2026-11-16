# Draft issue for `kilworks/echo-dot-rea`

Review, then post it yourself at https://github.com/kilworks/echo-dot-rea/issues/new
(or tell me to). Nothing here contains device-identifying data (no serial, DSN or MAC).

---

**Title:** Offer: `doebrite` (Echo Dot 3 w/ clock, Fire OS 6) as a second documented target

**Body:**

Thanks for this repo — the `biscuit` write-up and the REA method are a great template.

I applied the same approach to a different device, the **Echo Dot 3rd gen with clock**
(model `36EBT3`, codename **`doebrite`**, Fire OS 6.5.7.5 / Android 7.1.2, MediaTek
MT8167, 32-bit userland), entirely from the public OTA — no teardown, no network
tampering. I'd be happy to contribute it as a second target if you're open to it, or
keep it as a sibling repo you link to; your call.

What's different from `biscuit`, and already documented with REA/Ghidra evidence:

- **OTA format changed.** Fire OS 6 ships a single A/B `payload.bin` (Android
  `update_engine`), not `system.new.dat` + `system.transfer.list`. Extraction is
  `payload_dumper` → `unsquashfs` (the `/system` image is squashfs/zstd), not
  `sdat2img` + `debugfs`.
- **The Alexa stack is completely different.** No `alexad`/`libalexad.so`. `doebrite`
  runs **Alexa Hybrid Execution** (AlexaHybridLitespeed) — a local+cloud engine on the
  open AVS Device SDK, with a `LocalRequestOrchestrator` (on-device vs cloud routing),
  an `ArtifactManager` pulling NLU models over DAVS, and a TLS `ExecutionController`.
- **On-device IPC is ACE IPC**, which turns out to be LIPC carried forward:
  `aceipc-daemon` still identifies itself as `lipc-daemon`, and `libaceipc.so` is a
  **D-Bus** client (attachments moved from LIPC's shared-memory queues to inline byte
  arrays).
- **Attestation is DHAv2** (DAK + CSR + signed cert chain over a Binder/AIDL service),
  a step up from `biscuit`'s DHAv1 (RSA + HMAC).

I also did a light security pass on the three most promising static surfaces
(`aceipc-daemon` command exec, `libaceipc` message parsing, DHA) — all came back
clean/hardened, consistent with
[cgarrot/echo-dot-3-doebrite-research](https://github.com/cgarrot/echo-dot-3-doebrite-research)
(no OTA custom firmware) and
[Gamer92000/echo-dot-assist](https://github.com/Gamer92000/echo-dot-assist)
(`doebrite`: no known exploit). I'm careful **not** to duplicate cgarrot's dynamic
network/BLE work — my contribution is the static architecture map of the Alexa stack,
the way you did it for `biscuit`.

Happy to open a PR adding a `doebrite/` target (extraction notes + the six subsystem
docs), or to just share the repo link — whichever you'd prefer. Would a second target
fit the scope here?
