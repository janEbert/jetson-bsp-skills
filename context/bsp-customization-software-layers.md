# BSP customization — Software layers

The BSP layer atlas for Jetson / IGX customization. It covers:

- the critical pitfalls to avoid before touching any layer, and
- the full software-layer surface — across firmware, kernel,
  flashing, userspace, and tooling — including which layers are
  deliberately **not** customer-modifiable.

---

## Read This First — Critical Pitfalls

1. **Never patch the BPMP-FW DTB to "fix" UPHY / thermal / PMIC.**
   It is module-side firmware. The right knobs are `ODMDATA`, kernel-DT
   thermal zones, and MB1-BCT PMIC dts respectively. Editing the
   BPMP-FW DTB blob (the per-chip `tegra<chip>-bpmp-*.dtb` shipped in
   the BSP) can corrupt DRAM, brick the SOM, defeat thermal
   protection, and break secureboot/ratchet.
2. **Never treat power, thermal, or carrier changes as single-layer edits.**
   These concerns are cross-cutting. Editing only one layer
   (e.g., only nvpmodel for a CPU cap, only kernel DT for a regulator)
   creates inconsistent state the platform cannot detect. Audit every
   layer that could possibly own the knob, not just the most obvious
   one, on every such commit.

---

Layers are listed in the order they execute / take effect.

> **Path convention:** path patterns below use placeholders for parts
> that vary by target platform. Substitute the actual values for your
> target.
>
> - `<chip>` — chip-family numeric prefix in BSP file names (e.g.,
>   `234` for T234 / Orin, `264` for T264 / Thor).
> - `<chip-family>` — chip-family wildcard directory (e.g., `t23x`,
>   `t26x`).
> - `<cvm-sku>` — Jetson Module SKU (e.g., `p3701`, `p3767`).
> - `<cvb-sku>` — Jetson Carrier Board SKU (e.g., `p3737`, `p3768`).

### Firmware-level (pre-Linux)

| Layer | Path / artifact | When you must edit |
|---|---|---|
| BR-BCT | `bootloader/generic/BCT/tegra<chip>-br-bct-*.dts` | Boot media or partition layout changes |
| **MB1 pinmux** | `bootloader/generic/BCT/tegra<chip>-mb1-bct-pinmux-*.dtsi` (generated `pinmux.dtsi`) | **Always** |
| **MB1 GPIO defaults** | `bootloader/gpio.dtsi` / `bootloader/tegra<chip>-mb1-bct-gpio-*.dtsi` (generated) | **Always** |
| **MB1 pad voltage** | `bootloader/generic/BCT/tegra<chip>-mb1-bct-padvoltage-*.dtsi` (generated) | 1.8 V vs 3.3 V rails differ |
| MB1 PMIC / power tree | `bootloader/generic/BCT/tegra<chip>-mb1-bct-pmic-*.dts` | Carrier-side regulators differ |
| MB1 reset (BootROM PMIC reset) | `bootloader/generic/BCT/tegra<chip>-mb1-bct-reset-*.dts` | SC7 wake / reset sequence differs |
| MB1 misc / SCR / firewalls | `tegra<chip>-mb1-bct-misc-*.dts`, plus MB2-BCT scr/firewall files | Misc straps, debug-UART routing, EEPROM bridge |
| **MB2 BCT** | `bootloader/generic/BCT/tegra<chip>-mb2-bct-{misc,scr,firewall-*}-*.dts` | EEPROM presence, firewalls, firmware-load flags |
| BPMP-FW DT (**HIGH RISK — avoid**) | `bootloader/tegra<chip>-bpmp-*.dtb` (per module SKU) | clocks, regulators, memory, thermal, power domains ..etc related settings |
| **ODM data** | `ODMDATA=` in `<board>.conf` | **Always** if PCIe/USB3/Ethernet wiring differs |
| **EEPROM image / layout** | `bootloader/eeprom.bin`, layout `HR/JetsonEepromLayout.html` | If carrier has its own EEPROM |
| UEFI / extlinux | `bootloader/extlinux.conf.{emmc,sd,nvme}` | Kernel cmdline, `FDT=`, `OVERLAYS=` |
| TOS / OP-TEE manifest | `nv_tegra/tos-scripts/`, `nv_optee.tbz2` | Adding/removing TAs |
| Coprocessor firmware | `bootloader/{display-<chip>-dce.bin, camera-rtcpu-<chip>-rce.img, adsp-fw.bin, fsi-lk.bin, spe_<chip>.bin}` | Custom RCE / SPE FreeRTOS only |

### Kernel layer

| Layer | Path | When you must edit |
|---|---|---|
| DT — SoC layer | `hardware/nvidia/<chip-family>/nv-public/tegra<chip>-soc/*.dtsi` | New SoC binding only |
| DT — module layer | `nv-public/tegra<chip>-<cvm-sku>-*.dtsi` | Don't touch for carrier work |
| **DT — platform / carrier** | `nv-public/nv-platform/tegra<chip>-<board>+<cvm-sku>-xxxx-nv.dts` | **Always** — your main DT file |
| DT — overlays | `nv-public/overlay/tegra<chip>-*-overlay.dts` | 40-pin header, optional cameras, fan |
| **DT Makefile** | `kernel-devicetree/generic-dts/dts/Makefile` | **Always** (register your DTS) |
| Kernel defconfig | `kernel/kernel-jammy-src/arch/arm64/configs/defconfig` | Extra in-tree drivers (PHY, RTC, hwmon, sensors) |
| NVIDIA OOT modules | `nvidia-oot/`, `nvgpu/`, `nvethernetrm/`, `nvdisplay/`, `hwpm/`, `hardware/` | New hardware blocks only |
| Camera plugin manager / sensors | `nvidia-oot/drivers/media/i2c/`, `nv-platform/tegra<chip>-<board>-camera-*.dts` | New / different cameras |
| Firmware blobs | `kernel-jammy-src/firmware/`, `nv_tegra/.../lib/firmware/` | Non-default Wi-Fi/BT chip |

### Flashing / packaging layer

| Layer | Path | When you must edit |
|---|---|---|
| **Per-board `.conf`** | `Image/Linux_for_Tegra/<vendor>-<board>.conf` | **Always** |
| Common `.conf` includes | `<cvm-sku>.conf.common`, `<cvb-sku>.conf.common` | Source-only; override in your `.conf` |
| Partition layout XMLs | `tools/kernel_flash/flash_l4t_t<chip>_*.xml` | A/B, encryption, custom sizes |
| Initrd flash flow | `tools/kernel_flash/l4t_initrd_flash.sh` | Production scripting only |
| Disk-image creator | `tools/jetson-disk-image-creator.sh` | SD-card products |
| Capsule / BUP (OTA) | `build_l4t_bup.sh`, `l4t_generate_soc_bup.sh`, `generate_capsule/` | Field-update bundles |
| Fuse blobs (production) | `odmfuse.sh`, `nvmassfusegen.sh`, `bootloader/fuse_t<chip>.xml` | Secureboot, ODM keys, anti-rollback |

#### Per-board conf dispatch — `update_flash_args_common`

Each per-board `.conf` defines a dispatch function — typically
`update_flash_args_common` — that runs at flash time and selects
**every** SKU- / revision-dependent artifact for the build. **The
static `<X>=` lines in the per-board `.conf` are only base-SKU
defaults; the dispatch rewrites them.** Treat the dispatch's output
as authoritative — never read a static line at face value when the
target's SKU / revision differs from the conf's base.

Inputs (read from EEPROM at flash time, or supplied from the active
profile when running BSP-side resolution):

- `board_sku` — module SKU (e.g. `0003` for Orin Nano 8GB).
- `board_FAB` — fabrication / revision tag
  (e.g. `TS1`, `EB1`, `A01`; blank for production). Sourced from
  whichever of `reference_devkit.module.revision`,
  `reference_devkit.carrier.revision`, or
  `custom_carrier.revision` the dispatch keys on (typically
  module-side, but carrier-side dispatches exist too).

Typical dispatched artifacts (varies per product):

- `DTB_FILE` (kernel DTB), `BPFDTB_FILE` (BPMP-FW DTB),
  `TBCDTB_FILE` (TBC / Trusty DTB).
- `EMC_BCT`, `WB0SDRAM_BCT` (DRAM training tables).
- `PINMUX_CONFIG`, `PMC_CONFIG`, `PMIC_CONFIG`
  (MB1 BCT pinmux / pad-voltage / PMIC tree).

Why this matters for any skill that walks the BSP:
SKU-multiplexed carriers (Orin NX/Nano on P3768, AGX Thor on
P3971/P4071, etc.) all rely on this dispatch. Reading any `<X>=`
line at face value gives the wrong artifact for non-base SKUs or
non-production revisions, which then cascades into wrong runtime
behavior (wrong `compatible` string, wrong DRAM training, wrong PMIC
voltages, etc.). For BSP-side resolution: source the flash conf
chain, invoke `update_flash_args_common` with `board_sku` and
`board_FAB` from the active profile, and only then read the resulting
`<X>=` variables.

#### Detecting DTB and BCT files from a flash conf

> **Rule:** never trust the static `<X>=` lines in a per-board
> `.conf` — they are base-SKU defaults. Always run the dispatch with
> the active profile's `board_sku` and `board_FAB`, then read the
> resolved variables.

When a skill needs the actual kernel DTB, BPMP DTB, MB1 BCTs, or DRAM
training files for the active target:

```bash
( source <per-board>.conf       # follow symlinks: e.g. jetson-orin-nano-devkit.conf → p3768-…-a0.conf
  board_sku=<module.sku>        # from the active profile
  board_FAB=<module.revision>   # from the active profile (empty for production)
  update_flash_args             # or update_flash_args_common, whichever the conf defines
  for v in DTB_FILE BPFDTB_FILE PINMUX_CONFIG PMC_CONFIG PMIC_CONFIG EMC_BCT WB0SDRAM_BCT
  do echo "$v=${!v}"; done )
```

The resolved filenames live under:

- **Kernel DTB** (`DTB_FILE`, `TBCDTB_FILE`) → `Linux_for_Tegra/kernel/dtb/`.
- **BPMP DTB** (`BPFDTB_FILE`) → `Linux_for_Tegra/bootloader/generic/`.
- **MB1 BCTs** (`PINMUX_CONFIG`, `PMC_CONFIG`, `PMIC_CONFIG`) and
  **DRAM training** (`EMC_BCT`, `WB0SDRAM_BCT`) →
  `Linux_for_Tegra/bootloader/generic/BCT/` (DT source — compiled into
  binaries during flash).

### Userspace / rootfs layer

| Layer | Path | When you must edit |
|---|---|---|
| Boot-up scripts | `nv.sh`, `nvfb.sh`, `nvpower.sh`, `nvpmodel.sh` | Power-profile differences |
| **nvpmodel** | `rootfs/etc/nvpmodel/<your_board>.conf` | Custom thermal / PSU profile |
| **INA3221 / hwmon current thresholds** | `rootfs/etc/systemd/nvpower.sh` `setup_hwmon()` | **Always if carrier PSU rating ≠ devkit.** Programs `curr<N>_max` (warning) and `curr<N>_crit` (BPMP throttle) on the on-board INA3221 from `(power_budget_mW × 1000) / VDD_IN_mV`. Hardware backstop independent of nvpmodel; without it, hardware over-current trips at devkit values regardless of your nvpmodel envelope. |
| udev / modules-load / cmdline | `rootfs/etc/udev/rules.d/`, `etc/modules-load.d/`, `boot/extlinux/extlinux.conf` | Custom cmdline / overlays |
| X / Wayland / display config | `rootfs/etc/X11/xorg.conf.d/`, weston ini | Headless / DP-only / custom display |
| Jetson-IO presets | `tools/jetson-io/` | 40-pin header presets |
| systemd / first-boot units | `rootfs/etc/systemd/system/nv*.service`, `/opt/nvidia/.../*.service` | Carrier-specific service overrides |
| Wi-Fi / BT / cellular | Firmware blob path, regdomain, brcm_patchram | New radio module |

### Tooling layer

| Layer | Path | When you must edit |
|---|---|---|
| Board EEPROM programming | `tools/board_automation/`, `bootloader/chkbdinfo` | Production EEPROM write |
| Backup / restore | `tools/backup_restore/` | Golden-image dumps |

### What you don't touch

- Tegra SoC firmwares (MB1, MB2, BPMP-FW, etc.).
- Module-internal BCT/DTSI (DRAM timings, on-module PMIC, etc.).
