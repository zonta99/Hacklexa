# Device Health Attestation — DHAv2

How `doebrite` proves to Amazon that it is a genuine, unmodified Echo. Static read of
`amzn_dha_tool`, `libacehal_dha.so`, and `fireos-dha` (strings + symbols, no device).

## Headline: biscuit was DHAv1, doebrite is DHAv2

The 2nd-gen `biscuit` DHA was an RSA keypair plus an **HMAC over the serial**, signed
through Keymaster. `doebrite` keeps that primitive but adds a full **DHAv2 X.509
attestation**: a device attestation key (**DAK**), a **CSR** the device emits, and a
**signed certificate chain** installed back onto the device.

`amzn_dha_tool` (26 KB) subcommands:

| Flag | DHA version | Does |
|---|---|---|
| `-c/--create` | v1 | provisions the Amazon DHA (RSA keypair) onto the device |
| `-d/--display` | v1 | shows the DHA public modulus and its HMAC |
| `-o/--dump` | v1 | dumps the DHA public key/cert |
| `-t/--test` | v1 | self-test the provisioned DHA |
| `--get-csr` | **v2** | outputs the device's DHAv2 CSR |
| `--sign-csr` | **v2** | signs the CSR with the device's **DAK**, produces a cert chain |
| `--get-certificate` | **v2** | retrieves the DHAv2 cert chain |
| `--set-certificate` | **v2** | installs a DHAv2 cert chain from stdin |

It validates rigorously: `Invalid RSA public key/modulus`, `Unexpected RSA public
exponent`, `Mis-matched public Keys on device and DHAv2 leaf certificate`, `Sanity
test failed on device certificate`, `Unable to verify data using Keymaster API`. The
device identity comes from `/proc/idme/device_type_id` and the SoC serial — the same
idme partition the bootloader gates unlock on.

## HAL and service layering

```
fireos-dha  (service "amazon.security.dha", AIDL via libdha-aidl.so)
   │   wraps amzn_dha_module_t + amzn_idme_module_t, sets its own SELinux domain
   ▼
libacehal_dha.so  (ACE HAL shim)
   aceDhaHal_open / generateKey / getPublicKey / signData / verifyData /
   setCertificate / getField / close
   ▼
/system/lib/hw/amzn_dha.mt8167.so   (vendor HAL, SoC-specific)
   ▼
Amazon Keymaster device  (TEE-backed key ops; keys never leave the secure world)
```

So on `doebrite` attestation is a **Binder/AIDL system service** (`amazon.security.dha`)
on top of an ACE HAL shim on top of the MT8167 vendor HAL on top of **Keymaster** —
a cleaner, more layered stack than biscuit's direct tool→Keymaster path, and the
cryptography (DAK, signing, verification) runs in the TEE. `fireos-dha` also loads
the IDME module and configures SELinux for itself.

## Security read

DHAv2 is *stronger* than biscuit's DHA: a TEE-held DAK signing a CSR into a proper
cert chain, validated against the device key. Nothing here is a weakness — it is the
mechanism that makes a cloned or tampered device fail attestation, and it reinforces
why custom firmware can't masquerade as genuine. No attack surface of note in the
tool itself (it is an operator CLI). The interesting question for a follow-up is the
**AIDL service** `amazon.security.dha`: which SELinux domains may call `signData` /
`verifyData`, and whether any caller is reachable from a lower-privileged context.

## vs biscuit

| | biscuit (DHAv1) | doebrite (DHAv2) |
|---|---|---|
| Primitive | RSA keypair + HMAC over serial | DAK + CSR + signed X.509 cert chain (HMAC still present) |
| Exposure | `amzn_dha_tool` → Keymaster | AIDL service `amazon.security.dha` → ACE HAL → vendor HAL → Keymaster |
| Key custody | Keymaster (TEE) | Keymaster (TEE), DAK-based |
