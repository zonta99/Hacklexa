# Extraction

How the `doebrite` `/system` tree was recovered from the OTA, with no device access.
This differs from the `biscuit` (2nd gen) pipeline: Fire OS 6 ships an A/B
`payload.bin`, not the old `system.new.dat` + `system.transfer.list` block OTA, and
`/system` is **squashfs/zstd**, not ext4.

## 1. Download the OTA

```bash
scripts/download-ota.sh
```

Pulls `update-kindle-doebrite-NS6575_user_8349_0013323246980.bin` (118 MB) from
Amazon CloudFront (still served in the clear) and checks the MD5 against FTVDB
(`c79bbc974b96c69c9cd9ea083e8ecdca`). This is the exact build the target unit runs
(Alexa app → About → Device Software Version `13323246980`).

## 2. Unzip the OTA

The `.bin` is a SignApk ZIP. Unlike `biscuit`, it contains a single **`payload.bin`**
(Android `update_engine` / brillo A/B payload), plus metadata:

```
payload.bin                          123 MB   full A/B update payload
payload_properties.txt                        FILE_HASH / FILE_SIZE / METADATA_*
ota.prop                                       product=doebrite, Fire OS 6.5.7.5
system/build.prop, META-INF/*                  signing cert, target props
```

`ota.prop` confirms `binary_type=full`, so `payload.bin` carries complete partition
images — no base image needed.

## 3. Dump partitions from payload.bin

```bash
python3 -m venv .venv
./.venv/bin/pip install payload_dumper
./.venv/bin/payload_dumper --out extract/images extract/payload.bin
```

Yields: `system.img` (130 MB), `boot.img`, `lk.img` (bootloader), `tee1.img`/`tee2.img`
(TrustZone), `brhgptpl_0..3.img` (partition tables).

## 4. Extract /system (squashfs/zstd)

`system.img` is **squashfs v4.0, zstd-compressed**. Needs `unsquashfs` ≥ 4.5 with zstd:

```bash
brew install squashfs        # 4.7.5, has zstd
unsquashfs -d extract/system -no-xattrs extract/images/system.img
```

The Android `/system` tree lands under `extract/system/system/`. Read-only, no root.

## 5. Result

- 360 binaries in `/system/bin`, 697 shared objects in `/system/lib`.
- **All userland is ARM 32-bit (`armeabi-v7a`), EABI5** — no ARM64 userland.
- The Alexa stack is the **ACE framework + Alexa Hybrid Execution**, not the
  `biscuit`-era `alexad`/LIPC daemon. See [findings.md](findings.md).
