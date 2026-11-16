# Hacklexa

Static reverse engineering of the **Amazon Echo Dot 3rd gen with clock** (`doebrite`),
from the public OTA firmware, using [REA](https://github.com/morluto/rea). No device
teardown, no soldering, no network tampering — the entry point is the OTA image Amazon
still serves in the clear.

Method adapted from [`kilworks/echo-dot-rea`](https://github.com/kilworks/echo-dot-rea)
(which targets the 2nd gen `biscuit`). The goal here is the piece nobody has done for
`doebrite`: a full static decompilation of the on-device Alexa stack.

## Target

| Property | Value |
|---|---|
| Product | Echo Dot 3rd gen **with clock** |
| Model | `36EBT3` |
| Codename | `doebrite` |
| deviceType | `A30YDR2MK8HMRV` |
| OS | Fire OS 6.5.7.5 (`NS6575`), Android 7.1.2, build `13323246980` (2026-10-27) |
| SoC | MediaTek MT8167 |
| Userland | 100% 32-bit (`armeabi-v7a`) |
| USB | none exposed on the product |

Firmware identity is the exact build read from this unit's Alexa app → About
(Device Software Version `13323246980`).

## Prior art (do not duplicate)

- [`cgarrot/echo-dot-3-doebrite-research`](https://github.com/cgarrot/echo-dot-3-doebrite-research)
  — full `lk` disassembly, network/BLE attack surface, OTA integrity chain, CVEs.
  Concludes no custom firmware can be installed OTA.
- [`RobinFitzek/Alexa-Platform`](https://github.com/RobinFitzek/Alexa-Platform)
  — live-device network measurements, binary audit, CVE matrix.
- [`Gamer92000/echo-dot-assist`](https://github.com/Gamer92000/echo-dot-assist)
  — Home Assistant voice-satellite port; `doebrite` is listed as *no known exploit*.

**This repo's niche:** static decompilation and documentation of the Alexa daemon
and its libraries on `doebrite`, the way `kilworks` did for `biscuit`.

## Pipeline

1. **Download** the OTA `.bin` from Amazon CloudFront — `scripts/download-ota.sh`
   (URL and MD5 indexed by [FTVDB](https://ftvdb.com/echo/firmware/com.amazon.doebrite.android.os/)).
2. **Unzip** the `.bin` (it is a SignApk ZIP).
3. **Convert** `system.new.dat` + `system.transfer.list` to a raw ext4 image with
   `scripts/sdat2img.py` (xpirt, MIT).
4. **Extract** `/system` from the ext4 image read-only with `debugfs` — see `docs/extraction.md`.
5. **Analyze** the Alexa binaries with REA.

## Legal

Personal security research on hardware I own. Firmware images and extracted binaries
are Amazon's property and are **not** redistributed here (`firmware/` and `extract/`
are git-ignored). This repo holds only tooling, method, and derived analysis. Obtain
the OTA from Amazon's CDN yourself.
