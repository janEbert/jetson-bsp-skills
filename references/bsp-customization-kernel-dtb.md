# Kernel-DT Customizations Overlay

Single source of truth for how customize-* skills express their
kernel device-tree changes for a given active target. All Customize
kernel-DT edits land as fragments inside **one composite overlay
`.dts`** per active target; the composite is built and registered
by `jetson-build-source` and flashed via a single
`OVERLAY_DTB_FILE+=` line on the carrier flash conf.

**Audience:** every customize-* skill that emits kernel-DT changes
(currently `usb`, `camera`, `pcie`, `mgbe`, `uphy`; any future
sibling). Also `jetson-build-source`, which owns the build /
Makefile-registration / flash-conf-registration side, and
`jetson-derive-carrier`, which knows when the composite first
becomes addressable.

---

## Hard rule: no direct in-tree DTS / DTSI edits

Every kernel device-tree customization MUST be expressed as a
fragment inside the composite overlay defined below. **Direct edits
to in-tree `.dts` / `.dtsi` files under `<source.root_path>/bsp_sources/`
are forbidden for customize-\* skills**, including (but not limited
to) the chip-level SoC DTSI (e.g. `tegra234-soc-*.dtsi`), per-carrier
DTSI (e.g. `tegra234-p3768-0000+p3767.dtsi`), and per-platform DTS
(e.g. `tegra234-p3768-0000+p3767-0001-nv.dts`). Rationale:

1. **Clean upgrade path.** Direct edits collide with NVIDIA's
   pristine source tree on the next BSP rebase. Composite overlays
   live in the user-owned `*-xxxx-custom.dts` slot and survive
   rebases by construction.
2. **Per-fragment audit trail.** Every fragment carries a
   `/* custom-bsp: <skill-name>[:<sub-key>] */` marker. Grepping
   the composite is the single source of truth for "what's
   customized on this board". Direct in-tree edits scatter the
   audit trail across the entire DT and silently lose the
   skill-attribution metadata.
3. **Build-time gate keeps flashing safe.** `jetson-build-source`
   appends `OVERLAY_DTB_FILE+=",<name>.dtbo"` to the carrier flash
   conf **only when the composite `.dts` exists**, which guarantees
   the `.dtbo` gets compiled by `nvidia-dtbs` and is present at
   flash time. Bypassing the composite (a standalone overlay
   outside the slot, or a direct in-tree edit) breaks this
   invariant: the flash conf may reference a `.dtbo` that was
   never produced, and `flash.sh` aborts mid-flash with a
   missing-file error.

Exceptions: none for customize-\* skills. The base BSP tree —
`tegra<soc>.dtsi`, NVIDIA-shipped per-platform DTSes, vendor SoC
DTSIs — is read-only at the customize-\* layer. Adjustments to
those go through NVIDIA upstream or [`jetson-derive-carrier`](../skills/jetson-derive-carrier/SKILL.md)
(the one skill that legitimately produces a new per-carrier DTS as
the **base** for a custom carrier — never an in-place patch of an
NVIDIA-shipped file). BPMP DTB edits (a different artifact, see
[`bsp-customization-bpmp-dtb.md`](bsp-customization-bpmp-dtb.md))
are outside the scope of this rule.

## Why one composite, not N standalone overlays

UEFI plugin-manager loads each entry in `OVERLAY_DTB_FILE` in order
and stops on first mismatch of the `compatible` gate. Carrying N
per-feature overlays multiplies the gate-mismatch surface, requires
N flash-conf appends to stay consistent, and makes the audit trail
of "what's actually customized on this board" fragmented across N
files.

NVIDIA's own `tegra<soc>-<carrier>+<module-sku>-dynamic.dtbo`
pattern already establishes the "one composite per board" idiom —
fragments inside it are gated per `board_config { ids = … }`. The
custom-overlay slot mirrors that idiom for *user* customizations.

## Canonical filename + location

| Active target field | Resolves to |
|---|---|
| `<soc>` | tegra chip suffix: `234` (Orin / T23x), `264` (Thor / T264) |
| `<carrier-id-sku>` | `<reference_devkit.carrier.id>-<reference_devkit.carrier.sku>` OR `<custom_carrier.carrier.id>-<custom_carrier.carrier.sku>` when a custom carrier is active |
| `<module-id>` | `<reference_devkit.module.id>` |

Composite filename: `tegra<soc>-<carrier-id-sku>+<module-id>-xxxx-custom.dts`

The `-xxxx` literal is mandatory — it parallels NVIDIA's `-dynamic.dts`
naming and signals "this composite is module-SKU-agnostic; per-SKU gating
happens inside via `board_config { ids = … }`."

Per-chip directory (mirrors where NVIDIA places its `-dynamic.dts`):

| `<soc>` | Directory inside `<source.root_path>/bsp_sources/hardware/nvidia/` |
|---|---|
| `234` (T23x / Orin) | `t23x/nv-public/overlay/` |
| `264` (T264 / Thor) | `t264/nv-public/nv-platform/` |

Concrete examples:

| Active target | Composite path |
|---|---|
| IGX Thor T5000 (p4071-0000 + p3834-0008) | `t264/nv-public/nv-platform/tegra264-p4071-0000+p3834-xxxx-custom.dts` |
| AGX Orin devkit (p3737-0000 + p3701-0000) | `t23x/nv-public/overlay/tegra234-p3737-0000+p3701-xxxx-custom.dts` |

Compiled output (produced by `nvidia-dtbs`): same basename with
`.dtbo` extension at `<source.root_path>/bsp_sources/kernel-devicetree/generic-dts/dtbs/<name>.dtbo`.

Promote destination (via `jetson-build-source`'s manifest):
`<bsp_image.root_path>/Linux_for_Tegra/kernel/dtb/<name>.dtbo`.

## Skeleton

When the composite does not yet exist (first kernel-DT customization
on this target), the **first customize-* skill to run** creates it
using this skeleton:

```dts
// SPDX-License-Identifier: GPL-2.0-only
// Composite kernel-DT customization overlay for <carrier-id-sku> + <module-id>.
// Authored jointly by customize-* skills; each appends fragments via the
// protocol in .claude/references/bsp-customization-kernel-dtb.md.
// jetson-build-source owns the Makefile + OVERLAY_DTB_FILE registration.

/dts-v1/;
/plugin/;

/ {
    overlay-name = "<carrier-id-sku>+<module-id>-xxxx Custom Overlay";
    compatible = "nvidia,<carrier-id-sku>+<module-id>-<module-sku>",
                 "nvidia,tegra<soc>";

    /* customize-* fragments appended below this line. */
};
```

`compatible` rules:

- MUST contain ≥1 string that appears in the live DUT's
  `/proc/device-tree/compatible`. UEFI plugin-manager skips
  overlays whose gate doesn't match. Verify with
  `cat /proc/device-tree/compatible | tr '\0' '\n'` on a booted
  DUT, or by decompiling the carrier's base `.dtb` and reading
  `/compatible`.
- For a custom carrier, use the carrier-id-sku from
  `custom_carrier.carrier`, not the reference devkit's, because
  `jetson-derive-carrier` rewrites the base DTB's `compatible` to
  the custom carrier identity.
- Reuse the same string list across the composite skeleton and
  every fragment. Don't widen `compatible` per-fragment — the gate
  is at the overlay root.

## Append protocol (customize-* skills)

Every customize-* skill that mutates kernel device-tree state
follows this protocol exactly. Do not deviate.

1. **Resolve the composite path** for the active target using the
   filename + per-chip directory rules above. Treat the path as
   `<COMPOSITE>` below.

2. **If `<COMPOSITE>` does not exist** → create it from the
   skeleton template above, filling in `<carrier-id-sku>`,
   `<module-id>`, `<module-sku>`, `<soc>` from the active profile.
   This is the **only** time the file is created from scratch.

3. **Compute the next free `fragment@N` index** — scan existing
   `fragment@N { … };` blocks in `<COMPOSITE>`, take the max N,
   add 1. Use this for the new fragment(s) you're appending.
   If you emit multiple fragments in one invocation (e.g.
   `customize-usb` emitting one per port), allocate consecutive Ns.

4. **Each fragment carries a mandatory marker comment** so the
   skill can find its own fragments on re-run, and an audit reader
   can tell who owns what:

   ```dts
   fragment@<N> { /* custom-bsp: <skill-name>[:<sub-key>] */
       target = <&node-or-path>;
       __overlay__ {
           …;
       };
   };
   ```

   `<skill-name>` is the short tail of the skill identifier
   (`mgbe`, `pcie`, `usb`, `camera`, `uphy`). `<sub-key>` is an
   optional discriminator (e.g. `mgbe0`, `pcie@2`, `usb3-port-3`)
   when the skill produces multiple fragments — required when
   more than one fragment per skill is appended.

5. **Idempotency on re-run** — when the skill runs again with
   different inputs, it **deletes its own previously-tagged
   fragments first**, then appends the new ones at the current
   next-free index. Grep pattern for the delete pass:
   `/\* custom-bsp: <skill-name>(:<sub-key>)? \*/`. Never
   leave two fragments with the same `(skill-name, sub-key)`
   marker.

6. **No `/dts-v1/;`, no `/plugin/;`, no `overlay-name`, no
   `compatible` inside fragments** — those live on the composite
   root only. A fragment is `fragment@N { target = …; __overlay__
   { … }; };` and nothing else.

7. **No `#include` inside the composite** for headers the skill
   would have brought in standalone (e.g. `dt-bindings/gpio/…`).
   Resolve numeric constants in the skill before writing. Rationale:
   `#include` chains have to be deduplicated across fragments, and
   `dtc -@` doesn't preprocess includes — the build path runs cpp
   first, but the canonical surface is post-cpp text only. Keep
   each fragment self-contained at the value level.

8. **Commit in `bsp_sources/`** with a message that names both the
   skill and the change scope:

   ```bash
   git -C <source.root_path>/bsp_sources add <relative-path-to-composite>
   git -C <source.root_path>/bsp_sources commit -m \
       "jetson-customize-<skill-name>: append <scope> to <board-tag>-custom"
   ```

   One commit per customize-* invocation. Don't squash multiple
   skills' edits into one commit — that defeats the per-skill
   audit trail. Cross-skill rebases that produce the same final
   file content are fine post-hoc.

9. **Do NOT register the composite in the per-dir Makefile.** Do
   NOT touch the carrier flash conf. Both belong to
   `jetson-build-source`'s "Register composite custom overlay" step. If the
   composite was just created in the per-skill append step above, `jetson-build-source` will
   add the registration on its next run.

10. **Pre-flight `dtc` + `fdtoverlay` sanity check.** Before
    committing, compile the composite locally and verify it merges
    against the carrier's reference `.dtb`:

    ```bash
    cpp -nostdinc -I . -x assembler-with-cpp <COMPOSITE> /tmp/composite.tmp.dts
    dtc -@ -I dts -O dtb -o /tmp/composite.dtbo /tmp/composite.tmp.dts
    fdtoverlay -i <bsp_image.root_path>/Linux_for_Tegra/kernel/dtb/<carrier-base>.dtb \
               -o /tmp/merged.dtb /tmp/composite.dtbo
    ```

    Fail the commit (`git restore --staged <COMPOSITE>` and exit
    non-zero) if either step errors. `jetson-build-source` runs
    the real build via `nvidia-dtbs`; this is a pre-flight check
    only.

## Build / registration ownership (jetson-build-source)

`jetson-build-source` is the only skill that mutates the build
side of the composite. On every DT-touching invocation (modes
`dt` and `full`):

1. **Discover the composite path** for the active target using
   the rules above. If `<COMPOSITE>` does not exist, skip — the
   target has no kernel-DT customizations yet; no build, Makefile,
   or flash-conf work to do.

2. **Ensure the per-dir Makefile registers it.** Idempotent
   append (skip if the exact line already exists):

   ```make
   dtbo-y += <composite-basename>.dtbo
   ```

   The per-dir Makefile is `<source.root_path>/bsp_sources/hardware/nvidia/<chip-dir>/nv-public/<sub>/Makefile`
   where `<sub>` matches the composite's directory.

3. **Ensure the carrier flash conf has the `OVERLAY_DTB_FILE+=`
   line.** Idempotent append (skip if the exact `# custom-bsp:
   composite` comment terminator already exists):

   ```sh
   OVERLAY_DTB_FILE+=",<composite-basename>.dtbo"; # custom-bsp: composite
   ```

   The carrier flash conf path is read from
   `custom_carrier.flash_config` (custom carrier) or
   `reference_devkit.flash_config` (reference devkit) of the
   active profile, resolved under the overlay tracker
   `<source.root_path>/Linux_for_Tegra/`.

   **Order matters** — the composite must come AFTER the
   `…-dynamic.dtbo` line (so dynamic gating runs first, then user
   customizations). The append-only convention guarantees this.

4. **Commit the Makefile + flash-conf changes** as two separate
   commits in their respective trackers (`bsp_sources/` mono-repo
   for the Makefile patch; `<source.root_path>/Linux_for_Tegra/`
   overlay tracker for the flash-conf patch). Both commits go
   through the workflow's pristine + customization pair when the
   target file is being touched for the first time.

5. **Manifest entry** — record the composite `.dtbo` as a manifest
   artifact with `kind: dtb`, `src: <generic-dts/dtbs/<name>.dtbo>`,
   `dst: kernel/dtb/<name>.dtbo`, `source_repo: hardware/nvidia/<chip-dir>/nv-public`
   when the composite's source repo is dirty (per the trace-to-dirty
   policy).

## Re-runnability + cleanup

- **Delete a customization** — re-run the originating customize-*
  skill with the customization disabled (e.g. `customize-pcie`
  with the controller set to disabled status). The skill removes
  its prior fragments and writes the new one with the new state.
  If the new fragment is a no-op, the skill emits **no** fragment;
  the prior-fragment delete pass cleans the previous state.
- **Delete all customizations** — manually `git restore` the
  composite to empty skeleton, or `rm` it and commit. On the next
  `jetson-build-source` run, missing composite means "no
  customizations" — skip the build / registration / flash-conf
  steps.
- **Inspect** — `grep '/\* custom-bsp:' <COMPOSITE>` lists every
  customize-* fragment in the composite.

## See also

- [`bsp-customization-workflow.md`](../context/bsp-customization-workflow.md) —
  where this fits in Customize / Build.
- [`bsp-customization-software-layers.md`](../context/bsp-customization-software-layers.md) —
  why kernel-DT overlays live in `bsp_sources/` and not in the
  `Linux_for_Tegra/` overlay tracker.
- [`../skills/jetson-build-source/SKILL.md`](../skills/jetson-build-source/SKILL.md) —
  the build / registration / flash-conf owner.
- Per-skill append integrations:
  - `jetson-customize-mgbe`
  - `jetson-customize-pcie`
  - `jetson-customize-usb`
  - `jetson-customize-camera`
  - `jetson-customize-uphy`
