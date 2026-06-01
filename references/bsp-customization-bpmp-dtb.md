# BPMP-DTB Customization

Single source of truth for how customize-* skills directly edit the
BPMP firmware device tree (the per-chip, per-module-SKU
`tegra<chip>-bpmp-*.dtb` blob in `Linux_for_Tegra/bootloader/`).
Edits to BPMP-DTB are **overlay-only** — they do not pass through
Build (`jetson-build-source`). Each edit is a decompile → edit
→ recompile round-trip using `dtc` alone; no kernel headers, no
cpp, no Makefile registration.

**Audience:** every customize-* skill that needs to change a
property inside the BPMP firmware DT (currently `clocks`; future
candidates include direct thermal-trip / regulator / power-domain
edits when ODMDATA-token coverage doesn't reach them). Also
`jetson-promote-image`, which copies the edited `.dtb` into
`bsp_image` via the overlay channel.

---

## When to edit BPMP-DTB directly vs. ODMDATA

BPMP-FW DT controls clocks, regulators, memory, thermal, power
domains, UPHY lanes, FMON config, and other early-boot policy.
There are **two ways** to mutate it; pick the right one per change:

| Mechanism | When to use | Owner |
|---|---|---|
| **ODMDATA tokens** (`uphy0-config-N`, `mgbe0_speed=…`, etc.) | NVIDIA-documented dispatch knob exists for the property. Token consumed at flash time by `tegraflash_update_bpmp_dtb()` and merged into the BPMP DTB just-in-time. | `jetson-customize-uphy`, `jetson-customize-mgbe` (edit the carrier flash conf's `ODMDATA="..."` line) |
| **Direct DTS edit** (this doc) | No ODMDATA token covers the change, or the token has known footguns (silent rejection / wrong semantics). Edit the static `.dtb` in the overlay tracker; the change persists across flashes. | [`jetson-customize-clocks`](../skills/jetson-customize-clocks/SKILL.md) (e.g. `max-rate-custom` on a clock node); future thermal-cap / regulator skills |

**Coexistence rule.** ODMDATA tokens are applied *on top of* the
static DTB at flash time. If both a direct edit and an ODMDATA
token target the same property, the ODMDATA pass wins — it runs
after the static blob is read. Use direct edits only for
properties no ODMDATA token reaches. Conversely, never set a
direct edit to "undo" an ODMDATA token from the same carrier conf
— you'll get a confusing flip-flop on next flash.

**HIGH-RISK reminder.** BPMP-FW DT is firmware-layer state read
before the kernel exists. A wholesale rewrite, or an edit to
nodes whose semantics aren't documented (PMIC sequencing, DRAM
training tables, EMC ladder, etc.) can brick the board.
`bsp-customization-software-layers.md` flags BPMP-FW DT as HIGH
RISK for a reason. Stick to **targeted property edits on named
clock / thermal / regulator nodes documented elsewhere in this
context tree**; never replace whole subtrees.

## Resolving the active BPMP DTB

The BPMP DTB lives under `Linux_for_Tegra/bootloader/generic/`
as the canonical per-SKU source. The flash tool reads from this
location at flash time; a top-level `bootloader/<BPMP_BASENAME>`
working copy may also appear, but it is **flash-time derived
from the `generic/` source** — customizations only need to
update the `generic/` copy. Don't track or write the top-level
`bootloader/<BPMP_BASENAME>` from this skill; the next flash
re-derives it.

Per-board conf dispatch selects which `BPMP_BASENAME` is active
via `BPFDTB_FILE` in the flash conf:

```bash
# Active flash conf lives in the overlay tracker (after first-touch
# pristine import — see `bsp-customization-workflow.md`) or in
# bsp_image otherwise.
FLASH_CONF=<source.root_path>/Linux_for_Tegra/${ACTIVE_FLASH_CONFIG}
[ -f "$FLASH_CONF" ] || FLASH_CONF=<bsp_image.root_path>/Linux_for_Tegra/${ACTIVE_FLASH_CONFIG}

BPMP_BASENAME=$(awk -F'="' '/^BPFDTB_FILE=/ {gsub(/";?$/,"",$2); print $2}' "$FLASH_CONF")

# Single relative path — the canonical generic/ source.
BPMP_REL="bootloader/generic/${BPMP_BASENAME}"

# Overlay-tracker copy (EDIT target):
BPMP_OT=<source.root_path>/Linux_for_Tegra/${BPMP_REL}

# bsp_image copy (PRISTINE source for first-touch import):
BPMP_UP=<bsp_image.root_path>/Linux_for_Tegra/${BPMP_REL}
```

Example for IGX Thor T5000 (p4071-0000 + p3834-0008):
- `BPFDTB_FILE="tegra264-bpmp-3834-0008-4071-xxxx.dtb"`
- Overlay tracker edit target:
  `<source.root_path>/Linux_for_Tegra/bootloader/generic/tegra264-bpmp-3834-0008-4071-xxxx.dtb`

If the carrier flash conf is a symlink (the `jetson-agx-thor-devkit.conf
→ p3834-0008-p4071-0000-nvme.conf` case), resolve the symlink to its
real target before reading `BPFDTB_FILE`; otherwise pristine-import the
symlink as-is and read through it.

## Edit procedure

Every customize-* skill that mutates the BPMP DTB follows this
procedure exactly. Do not deviate.

### Pristine import on first touch

If `$BPMP_OT` does not exist in the overlay tracker, copy it from
`$BPMP_UP` and commit as the pristine baseline. The workflow
contract (see
[`bsp-customization-workflow.md`](../context/bsp-customization-workflow.md#commit-batching-in-the-overlay-tracker))
requires a user-acceptance gate before this commit.

```bash
OT=<source.root_path>/Linux_for_Tegra
if [ ! -f "$BPMP_OT" ]; then
  [ -f "$BPMP_UP" ] || refuse "BPMP DTB $BPMP_UP not found in bsp_image."
  mkdir -p "$(dirname "$BPMP_OT")"
  cp -p "$BPMP_UP" "$BPMP_OT"
  git -C "$OT" add "$BPMP_REL"
  git -C "$OT" commit -m "pristine: import $BPMP_BASENAME from bsp_image"
fi
```

The pristine commit is the audit anchor: subsequent customization
commits diff against it. The pristine .dtb is byte-identical to
the shipped artifact — reviewers can verify with `git show
HEAD:$BPMP_REL | sha256sum` against the bsp_image copy.

### Decompile

`dtc` only — no cpp, no kernel headers, no DTC_INCLUDE flags. The
shipped `.dtb` is fully flattened (all macros resolved, all
includes inlined at NVIDIA build time).

```bash
WORK=$(mktemp -d)
dtc -I dtb -O dts -o "$WORK/bpmp.dts" "$BPMP_OT"
```

The decompiled DTS will have `__symbols__` and `__fixups__`
sections at the bottom — leave them alone. They're part of the
phandle resolution machinery; round-trip through dtc preserves
them automatically.

### Edit the DTS

Targeted property edits on named nodes. Never replace whole
subtrees; never reorder children; never re-number phandles by
hand. Each skill targets nodes it owns by documented convention:

| Skill | Target nodes | Reference |
|---|---|---|
| `jetson-customize-clocks` | named clock nodes (`cluster0_clk`, `gpusys`, `dram`, …) — `max-rate-custom` property | [`../skills/jetson-customize-clocks/references/bpmp-dtb-clock-edits.md`](../skills/jetson-customize-clocks/references/bpmp-dtb-clock-edits.md) |
| _TODO: thermal-cap skill_ | named thermal nodes — trip-temperature properties | _TODO_ |
| _TODO: regulator skill_ | named PMIC nodes — voltage / current properties | _TODO_ |

**No in-DTS marker for audit.** Unlike the kernel-DT composite
overlay (where `/* custom-bsp: <skill>:<sub-key> */` comments tag
each fragment), the BPMP DTB is a binary that survives only as
the recompiled `.dtb` — `dtc` strips DTS comments on round-trip.
Audit lives in the overlay tracker's `git log` instead: commit
messages must name the skill, the node(s) touched, and the
properties changed, so `git log --oneline -- $BPMP_REL` becomes
the canonical change history.

### Recompile

```bash
dtc -I dts -O dtb -o "$WORK/bpmp.dtb" "$WORK/bpmp.dts"
```

`dtc` may print warnings (e.g. `unit_address_vs_reg`) inherited
from NVIDIA's source. These are benign on round-trip; suppress
with `-Wno-unit_address_vs_reg` if the noise is distracting, but
do not pass `-q` (a hard error during recompile must surface).

### Sanity-check the recompiled blob

Before overwriting the overlay-tracker copies, verify the
recompiled blob is structurally sane:

```bash
# 5a. dtc round-trip must succeed.
dtc -I dtb -O dts "$WORK/bpmp.dtb" >/dev/null

# 5b. Decompiled DTS must contain the new property value.
dtc -I dtb -O dts "$WORK/bpmp.dtb" | grep -F "<expected new value>" \
  || refuse "Recompiled DTB does not contain the expected edit."

# 5c. Sanity-cap on blob size — a wholesale truncation would shrink it
# dramatically. Refuse if the recompiled size is <90% or >150% of the
# pristine baseline.
ORIG=$(stat -c %s "$BPMP_OT")
NEW=$(stat -c %s "$WORK/bpmp.dtb")
python3 -c "import sys; o,n=$ORIG,$NEW; sys.exit(0 if 0.9*o <= n <= 1.5*o else 2)" \
  || refuse "Recompiled DTB size ($NEW B) outside sanity band vs pristine ($ORIG B)."
```

### Stage in the overlay tracker (customization commit)

Replace the overlay-tracker copy and commit. Acceptance gate
applies before this commit as well.

```bash
cp -p "$WORK/bpmp.dtb" "$BPMP_OT"
git -C "$OT" add "$BPMP_REL"
git -C "$OT" commit -m "$BPMP_BASENAME: <skill-name> — <node> <property> <delta>"
```

Commit-message convention (used as the audit trail):
- Subject: `<BPMP_BASENAME>: <skill-name> — <node> <property> <delta>`
- Body: cite the input doc (Adaptation Guide section, ODMDATA-token
  alternative considered and why direct edit was chosen), the
  pristine HEAD SHA, and any cross-skill dependencies.

Multiple customize-* invocations against the same BPMP DTB stack
naturally: each round-trips through dtc, applies its property
edit, and commits. Subsequent skills see the latest .dtb (which
already carries prior skills' edits).

### Cleanup

```bash
rm -rf "$WORK"
```

Don't leave the temp DTS in the tree — the .dtb is the only
durable artifact.

## Re-runnability + idempotency

- **Re-run a customize-* skill** — the skill decompiles the
  current overlay-tracker `.dtb`, finds and replaces its own
  target property (by named node + property key), recompiles, and
  commits. The property edit is naturally idempotent: setting
  `max-rate-custom = <0x77359400>` (2.0 GHz) when it's already that value
  produces a no-op `git diff`.
- **Delete a customization** — re-run the skill with the
  customization disabled, OR hand-edit the DTS to remove the
  property (then recompile + commit). For property-add edits
  (`max-rate-custom`), removing the line returns the node to
  upstream behavior. For property-modify edits (where the
  property exists upstream), restore the upstream value by
  comparing against the pristine commit.
- **Reset to pristine** — `git -C $OT checkout <pristine-commit>
  -- $BPMP_REL` followed by a commit. The pristine commit is the
  baseline anchor; never delete it.

## Coordination with `tegraflash_update_bpmp_dtb()`

At flash time the NVIDIA flasher runs
`tegraflash_update_bpmp_dtb()` (see
`jetson-customize-uphy`
for the token grammar). The function reads ODMDATA tokens off
the active flash conf's `ODMDATA="..."` line and applies them to
whatever `.dtb` ships in `bootloader/` (i.e. the file this doc
edits). Order of operations at flash time:

1. Static DTB read from `bootloader/$BPMP_BASENAME` — **this is
   the file the "Stage in the overlay tracker" step above commits**.
2. ODMDATA pass parses tokens, applies overrides.
3. Result baked into the flashed BPMP-FW partition.

So **a direct edit to the static DTB is overwritten by any
ODMDATA token that targets the same property**. Pick one
mechanism per property; never both.

## Promote / flash path

No changes to Deploy tooling. The edited `.dtb` lives in the
overlay tracker; `/jetson-promote-image`'s channel-A walk
copies it into `bsp_image/Linux_for_Tegra/bootloader/`;
`/jetson-flash-image` flashes from there.

The build-manifest channel (B) is **not** involved — BPMP DTB
edits never enter `Source/.build-manifest.yaml` because
`/jetson-build-source` doesn't run for them.

## Gotchas

- **Edit `generic/` only.** The canonical BPMP DTB source is
  `bootloader/generic/<BPMP_BASENAME>`. The top-level
  `bootloader/<BPMP_BASENAME>` working copy that may also exist
  on disk is flash-time-derived from the `generic/` source —
  the next flash overwrites it from `generic/`. Customizations
  only update `generic/`; don't track `bootloader/<BPMP_BASENAME>`
  in the overlay tracker, and don't write to it in `bsp_image`.
  Some BSP releases ship that working copy as root-owned with
  restrictive perms, which would force a sudo-escalation in
  `/jetson-promote-image` for no benefit — the value flows
  through `generic/` either way.
- **Don't edit the upstream copy at
  `<bsp_image.root_path>/Linux_for_Tegra/bootloader/generic/`.**
  It's `/jetson-promote-image`'s output, not an input. The edit
  target is always the overlay-tracker copy.
- **Symlinked flash conf, real BPMP DTB.** Some carriers ship the
  per-board conf as a symlink to a `-nvme.conf` / `-emmc.conf`
  variant. The `BPFDTB_FILE` value is the same regardless of
  which symlink resolves to it, but be careful when staging the
  flash conf into the overlay tracker — copying through a symlink
  pulls the real file content. (Same as the kernel-DT carrier-conf
  pristine-import flow.)
- **`__symbols__` and `__fixups__` survival.** dtc preserves
  these on round-trip automatically, but only if you don't strip
  them in your edit pass. Use property-level edits (`sed -i` on
  named nodes, or programmatic DT libraries that understand the
  full schema), not blunt `sed s/.../.../g` against the whole DTS.
- **Phandle stability.** Phandles are assigned by dtc on
  recompile. Adding a *new node* that didn't exist upstream can
  shift phandle numbering; downstream nodes referencing it by
  phandle integer may break. The safe form is "property edit on
  an existing node" — never structural changes.
- **No in-file audit marker.** The `/* custom-bsp: ... */`
  convention from `bsp-customization-kernel-dtb.md` does **not**
  apply here — dtc strips comments. The overlay tracker's `git
  log` is the only audit trail; the commit-message convention in
  the "Stage in the overlay tracker" step is therefore load-bearing.
- **HIGH-RISK area, narrow edit surface.** Don't be tempted to
  "fix" UPHY config, FMON limits, PMIC sequencing, or DRAM
  training by hand-editing this DTB. Those are reachable via
  ODMDATA tokens or other NVIDIA-supported knobs. Direct edits
  belong only to properties documented as customer-tunable
  (clocks' `max-rate-custom`, future per-skill conventions).
- **Round-trip diff stability.** `dtc -I dtb -O dts` may emit
  numeric values in a different style than the original
  source (hex vs decimal, ordering of properties). The `.dtb`
  may therefore differ byte-for-byte from upstream after a no-op
  round-trip. That's fine — the *semantic* diff is what reviews
  inspect, via a `git difftool` shim that pipes both sides
  through `dtc -I dtb -O dts` before diffing.
- **dtc version drift.** Different distros ship different dtc
  versions. Pin the dtc invocation to the BSP's bundled tooling
  when possible: `<bsp_image.root_path>/Linux_for_Tegra/kernel/dtc`
  (when present) or the system dtc otherwise. A version-mismatch
  round-trip produces benign diffs but can confuse reviewers.

## See also

- [`bsp-customization-workflow.md`](../context/bsp-customization-workflow.md) —
  where this fits in Customize (overlay-only edit, no Build).
- [`bsp-customization-software-layers.md`](../context/bsp-customization-software-layers.md#per-board-conf-dispatch--update_flash_args_common) —
  `BPFDTB_FILE` resolution and the HIGH-RISK warning header.
- [`bsp-customization-kernel-dtb.md`](bsp-customization-kernel-dtb.md) —
  sibling contract for the *kernel* DTB customizations (which DO
  require a Build via `nvidia-dtbs`).
- [`../skills/jetson-customize-clocks/references/bpmp-dtb-clock-edits.md`](../skills/jetson-customize-clocks/references/bpmp-dtb-clock-edits.md) —
  clock-specific node + property reference; the first concrete
  consumer of this protocol.
- [`../skills/jetson-build-source/SKILL.md`](../skills/jetson-build-source/SKILL.md) —
  Build builder; does **not** process BPMP-DTB edits (Overview
  paragraph cites this doc as the BPMP-DTB owner).
- [`../skills/jetson-promote-image/SKILL.md`](../skills/jetson-promote-image/SKILL.md) —
  Deploy promoter; channel A copies the edited `.dtb` from the
  overlay tracker into `bsp_image`.
