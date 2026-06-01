# Jetson / IGX Platform Reference

This document catalogs the Jetson and IGX products.

## Product Form Factors

Jetson and IGX products are offered in two configurations:

- **Jetson Module (CVM)** — the production Compute-on-Module that contains the
  Tegra SoC, intended for integration with a customer-designed carrier
  board.
- **Jetson Developer Kit (CVM + CVB)** — a module (CVM) mounted on a NVIDIA-designed
  reference Carrier Board (CVB) that exposes I/O for evaluation and software development.


## Product / Chip / SKU / Flash Config / Token Mapping

- The default flash conf is the user-facing devkit symlink. variants extend it with
  storage, power, emulation flavours. See the suffix legend below for the meaning
  of each variant tag.
- For products that share a flash conf, the actual module SKU is selected at flash time by
 `update_flash_args*` dispatch reading the EEPROM-reported SKU.
- The **Product Token** column is a case-insensitive glob fragment
  matching NVIDIA filenames by product family (e.g. `Orin-Nano`,
  `AGX-Orin`, `IGX-Thor`) rather than SKU. The `*` characters are part
  of the token and substitute for any separator, so `*orin*nano*`
  matches `Orin-Nano`, `Orin_Nano`, `Orin Nano`, and `OrinNano` alike.
  Rows that share a documentation family share a token; for a new
  product row, pick the broadest fragment that uniquely identifies its
  docs.

| Product Name | Chip Family | CVM-SKU | CVB-SKU | Default flash conf | Variants | Product Token |
|--------------|-------------|---------|---------|--------------------|----------|---------------|
| Jetson AGX Orin 64GB | Orin (T234) | P3701-0005 | P3737-0000 | jetson-agx-orin-devkit.conf | -maxn, -qspi, -as-jao-32gb, -as-nx-16gb, -as-nx-8gb, -as-nano8gb, -as-nano4gb | `*agx*orin*` |
| Jetson AGX Orin 32GB | Orin (T234) | P3701-0004 | P3737-0000 | jetson-agx-orin-devkit.conf | (same as 64 GB) | `*agx*orin*` |
| Jetson AGX Orin Industrial | Orin (T234) | P3701-0008 | P3737-0000 | jetson-agx-orin-devkit-industrial.conf | -maxn, -qspi | `*agx*orin*` |
| Jetson Orin NX 16GB | Orin (T234) | P3767-0000 | P3768-0000 | jetson-orin-nano-devkit.conf | -nvme, -qspi, -a0-maxn (raw), -super, -super-nvme, -super-qspi, -super-maxn, -super-maxn-nvme | `*orin*nx*` |
| Jetson Orin NX 8GB | Orin (T234) | P3767-0001 | P3768-0000 | jetson-orin-nano-devkit.conf | (same as Orin NX 16GB) | `*orin*nx*` |
| Jetson Orin Nano 8GB | Orin (T234) | P3767-0003 / P3767-0005 | P3768-0000 | jetson-orin-nano-devkit.conf | (same as Orin NX 16GB) | `*orin*nano*` |
| Jetson Orin Nano 4GB | Orin (T234) | P3767-0004 | P3768-0000 | jetson-orin-nano-devkit.conf | (same as Orin NX 16GB) | `*orin*nano*` |
| IGX Orin| Orin (T234) | P3701-0008 | P3740-0002 | igx-orin-devkit.conf | -qspi | `*igx*orin*` |
| IGX-500 | Orin (T234) | P3701-0008 | P3971-0000 | igx-500.conf | -qspi | `*igx*500*` |
| Jetson AGX Thor T5000 | Thor (T264) | P3834-0008 | P4071-0000 | jetson-agx-thor-devkit.conf | — | `*agx*thor*` |
| Jetson AGX Thor T4000 | Thor (T264) | P3834-0000 | P4071-0000 | jetson-agx-thor-t4000.conf | — | `*agx*thor*` |
| IGX Thor T5000 | Thor (T264) | P3834-0008 | P4071-0008 | p3834-0008-p4071-0008-nvme.conf | — | `*igx*thor*` |
| IGX Thor T7000 | Thor (T264) | P3834-0008 | P3740-XXXX | p3834-0008-p3740-xxxx-nvme.conf | — | `*igx*thor*` |

## Flash Config Variant Suffix Legend

| Suffix | Meaning |
|--------|---------|
| `-maxn` | MAXN power profile baked in |
| `-qspi` | QSPI partitions only — no rootfs |
| `-nvme` / `-ufs` | target rootfs media |
| `-super` | Orin Nano "Super" performance profile |
| `-as-<X>` | devkit emulates module SKU `X` (different image flashed onto same hardware) |
