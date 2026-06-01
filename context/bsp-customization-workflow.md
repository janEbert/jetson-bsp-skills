# BSP Customization Workflow

End-to-end view of how a Jetson / IGX BSP customization flows from
an authoring command through to a flashed and validated device.
This document is the single map of the four-phase workflow; the
per-phase mechanics, contract, and edit protocol are documented in
sibling files referenced at the bottom.

**Audience:** anyone (engineer or skill) that needs to understand
where a given customize-* invocation sits in the larger pipeline,
which files / repos are touched at each step, and which skill is
responsible for which phase.

---

## Terminology

| Term | What it is |
|---|---|
| **Jetson Module (SOM)** | NVIDIA-manufactured part: Tegra SoC + DRAM + PMIC + module edge connector. |
| **Jetson Devkit** | NVIDIA reference design: Module + NVIDIA-designed reference **carrier board** + PSU + IO. Used for development. |
| **Custom Carrier Board** | Your in-house Carrier board. The same module plugs in; the carrier wires the connector out to product-specific IO. |

---

## At a glance

```
SETUP ──► CUSTOMIZE ──► BUILD ──► DEPLOY
          (per           (auto-chain   (promote → flash → validate;
           customize-*    from Customize three independently invokable
           call)          when source   skills; staged changes reach
                          repos changed) bsp_image here)
```

- **Setup** prepares the profile, BSP image, sources, and documents.
- **Customize** stages overlay-only customizations (e.g.
  `nvfancontrol.conf`, `nvpmodel.conf`) into the `Linux_for_Tegra/`
  overlay tracker via batched pristine + customization commits (one
  commit per logical customization step, covering every file the
  step touched — see "Commit batching" below). Source-repo edits
  (kernel / OOT / DT) commit in the source repo itself.
- **Build** rebuilds artifacts from source-repo edits and
  records them in `<source.root_path>/.build-manifest.yaml`. Build
  outputs stay in-tree under `bsp_sources/`; they are **not**
  staged into the overlay tracker. The manifest is the contract
  to Deploy.
- **Deploy** has two parallel input channels for `bsp_image`: the
  overlay tracker (Customize edits) and the build manifest
  (Build artifacts). `jetson-promote-image` walks both, then
  hands off to flash / validate. Deploy is always invoked
  explicitly — never auto-chained.

---

## Workflow invariants

Every BSP edit must satisfy the following invariants. Skipping any
one of them destroys the diff trail that overlay packaging, review,
and BSP-version migration all depend on.

**Derive target hardware facts from the active profile.** Before any
mutating setup, edit, build, promote, flash, or validate step, load the
active target per
[`target-platform-contract.md`](target-platform-contract.md). GPU driver
stack is a derived invariant: T234 / Orin uses nvgpu; T264 and later use
OpenRM. If the active platform, BSP release, or extracted image disagree,
stop before side effects and ask the user to correct or explicitly
override the mismatch.

**All BSP edits land in the workspace, not in upstream.** Edits go
to `<source.root_path>/Linux_for_Tegra/<rel>/<file>` (overlay path,
for files that live under `Linux_for_Tegra/` in upstream) or to the
relevant source repo's working tree (for kernel / OOT / hardware /
etc. source files). Overlay files get a **pristine-import commit**
(`cp` from `<bsp_image.root_path>` → overlay, then commit) before
the customization commit; source-repo files edit in place — the
clone HEAD is the pristine baseline. Upstream at
`<bsp_image.root_path>/Linux_for_Tegra/` is read only for pristine
imports; Deploy's `/jetson-promote-image` is the only place that
writes upstream, and flashing reads from upstream after promote.

Three invariants the workspace must satisfy:

- **File-level granularity, not subtree-level.** Only touched files
  are imported; sibling / parent-directory contents are not. Overlay
  packagers reconstruct self-contained subtrees from the workspace's
  relative-path layout.
- **Workspace is detached from flashing.** Flash reads upstream only;
  the workspace is never read by flash or required to be in sync for
  the device to boot.
- **Upstream is immutable after extraction.** Hand-editing upstream
  without the matching pristine + customization commits destroys the
  diff trail. Re-extracting a BSP invalidates every pristine commit;
  refresh by dropping workspace git history and restarting imports.

### Commit batching in the overlay tracker

When a single logical customization step touches multiple files
under `Linux_for_Tegra/`, the skill issues **at most two commits**
in the overlay tracker — never one commit per file:

1. **Pristine-import commit** — a single commit that copies every
   file the step will edit from `<bsp_image.root_path>` into the
   overlay (skipping any file that already has a prior pristine
   commit). Omit this commit entirely if every target file is
   already imported.
2. **Customization commit** — a single commit covering every
   in-place edit the step performed across all of those files. The
   commit message names each affected file (or controller / pin /
   port the file represents) plus the delta applied.

Per-file fan-out collapses, but the pristine / customization split
is preserved (baseline vs. delta). A `customize-pinmux` run that
rewrites three DTSIs produces one pristine + one customization
commit, not three pairs.

Steps that stage files at temporally distinct phases (e.g.
`customize-uphy` edits the carrier conf, then later appends an
`OVERLAY_DTB_FILE+=` line) commit separately — batching applies
within a single staging operation, not across phases.

### Commit message preview gate

Every commit a skill creates in the overlay tracker
(`<source.root_path>/Linux_for_Tegra/.git`) is gated on explicit
operator confirmation of the proposed commit message. The skill
must follow this sequence for each commit it intends to make
(pristine import AND customization — the gate fires per commit,
not per step):

1. `git add` the files the commit will cover.
2. Render the proposed commit message to the operator in a fenced
   preview block, immediately preceded by a one-line summary of
   the staged paths (`git diff --staged --name-status`):

   ```
   Staged for commit (4 files):
     M  p3834-0008-p8181-0001-nvme.conf
     A  bootloader/tegra234-mb1-bct-pinmux-p3834.dtsi
     A  bootloader/tegra234-mb1-bct-gpioint-p3834.dtsi
     A  bootloader/tegra234-mb1-bct-pmc-p3834.dtsi

   Proposed commit message:

       jetson-customize-pinmux: <custom-carrier> pinmux/gpioint/pmc DTSI customization
       <body lines>
   ```

3. Prompt the operator with three choices:
   - **accept** → run `git commit -m '<msg>'` verbatim.
   - **edit** → operator supplies a replacement message (header
     and/or body); the skill commits with the operator's message.
   - **cancel** → leave the index staged, do not commit; the skill
     hands control back so the operator can inspect / unstage /
     resolve manually.

4. Never auto-accept. The gate has no `--yes` flag, no env-var
   bypass, no timeout default. A skill that calls `git commit`
   without first surfacing the message to the operator violates
   this invariant.

**Pristine imports are gated too.** A pristine-import commit's
content is a deterministic `cp` out of `<bsp_image.root_path>`, but
the operator's acceptance is still required — to confirm the right
files are being imported from the right source, not to review the
file contents themselves. Treating pristine commits as rubber-stamp
violates this invariant.

The preview gate is independent of the batching rule: a two-commit
step surfaces two previews, each independently accepted. Identical
rule applies to source-repo commits (`bsp_sources/`) made by
customize-* skills.

### Off-skill edits

For BSP edits without a governing customize-* skill (one-off MB1 BCT
hand-edits, ad-hoc rootfs config tweaks, etc.), apply the standard
overlay-tracker recipe directly. The customize-* skills point at this
section instead of re-stating the recipe per-skill.

1. **Check overlay state.** For every file `<rel>/<file>` the run will
   touch, let `<src>` = `<bsp_image.root_path>/Linux_for_Tegra/<rel>/<file>`
   and `<dst>` = `<source.root_path>/Linux_for_Tegra/<rel>/<file>`. If
   `git -C <source.root_path>/Linux_for_Tegra log -- <rel>/<file>` lists
   at least one commit, the file is already imported — skip to step 3.
2. **Pristine import.** `mkdir -p $(dirname <dst>); cp -p <src> <dst>`.
   Then one batched pristine-import commit per
   [Commit batching](#commit-batching-in-the-overlay-tracker), gated by
   the [preview gate](#commit-message-preview-gate).
3. **Edit `<dst>`.** All edits land in `<source.root_path>`.
4. **Customization commit.** One batched commit per the same batching
   rule and preview gate, covering every file edited.

Editing `<bsp_image.root_path>` directly bypasses the overlay tracker;
`/jetson-promote-image` only walks files committed in
`<source.root_path>/Linux_for_Tegra/`. Hand-edits there are silently
lost on the next `/jetson-init-image` re-extract.

### User input prompt style

Use click-to-select controls for bounded choices. Use `Type Something`
when the value cannot be fully enumerated.

Order options by domain order when one exists. For releases, sort by
semantic version descending (newest first), with source-provided
recommendations only in descriptions. Otherwise sort alphabetically. Keep
`Type Something`, `skip`, and `cancel` fixed at the bottom in that order
when present.

For time-sensitive choices, generate labels from current source data and
avoid stale-prone wording such as "latest", "current", or "recommended"
unless the source uses that exact wording. Do not add synthesized
`(Recommended)` badges.

### quick_start_prefill contract

`jetson-quick-start` may pass `quick_start_prefill` to downstream setup
skills. The handoff is a convenience only; each downstream skill still
owns validation and writes for its profile block.

- Forward `quick_start_prefill.mode` to downstream setup skills for
  caller context. Do not re-ask for values the owning setup skill can
  determine safely from submitted prefill or its own documented
  profile/schema defaults (values the skill's SKILL.md explicitly
  declares as the no-input behavior, such as "download all artifacts"
  or `active: NA`). Ask only when required input is missing, invalid,
  ambiguous, conflicts with existing state, or requires an explicit
  override.
- Every questionnaire question that contributes to prefill must offer
  `skip`. A skipped answer is omitted from `quick_start_prefill`; the
  downstream skill asks again only if the value is required.
- If a real workflow choice also means "none" or "do not configure",
  name it explicitly (for example `no_custom_carrier` or `skip_docs`) so
  it cannot be confused with the prefill-level `skip`.
- Every prefilled value must be value-complete. If a choice requires a
  concrete value, collect that value in the same prompt; do not pass
  placeholders such as "pin a version later".
- Every value must come from an explicit user selection or typed input.
  Do not infer target platform, BSP release, source paths, document
  bindings, or carrier details from tarball names, repo names, document
  titles, runtime-inferred defaults, existing files, workspace state, or
  compatibility guesses. (This is distinct from the documented
  profile/schema defaults above: those are pre-declared no-input
  behaviors a skill may safely apply; runtime-inferred defaults are
  values guessed from the environment and must trigger a prompt.)
- A downstream skill may consume only its own subset. Missing, invalid,
  ambiguous, or incompatible prefill is a blocking gate: stop before side
  effects, ask using the user input prompt style, and never
  auto-substitute a different value. The skill that owns the profile block
  remains the only writer for that block.

---

## Flowchart

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                  BSP CUSTOMIZATION WORKFLOW (OVERLAY MODEL)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────────┐
│ SETUP (per workstation, one time)                                            │
│                                                                              │
│   /jetson-quick-start                                                        │
│      ▸ selects Auto Setup / Guided Setup / Use Existing Workspace            │
│      ▸ asks one core click-to-select setup questionnaire                     │
│      ▸ passes quick_start_prefill to each downstream setup skill             │
│                                                                              │
│   /jetson-init-target or /jetson-set-target                                  │
│      ▸ writes or activates target-platform/<name>.yaml                       │
│      ▸ records reference_devkit + optional custom_carrier details            │
│                                                                              │
│   /jetson-download-bsp (Auto Setup only)                                     │
│      ▸ lists supported BSP releases for the active platform                  │
│      ▸ fetches BSP/rootfs tarballs, public_sources.tbz2, x-tools.tbz2,       │
│        and release docs                                                      │
│                                                                              │
│   /jetson-init-image                                                         │
│      ▸ extracts Jetson Linux + sample rootfs tarballs into Image/            │
│      ▸ runs apply_binaries.sh with the target's GPU-stack flag               │
│      ▸ writes bsp_image.version and optional bsp_image.root_path             │
│                                                                              │
│   /jetson-init-source                                                        │
│      ▸ resolves <source.root_path> from profile                              │
│        (default: <workspace>/Source)                                         │
│      ▸ resolves source.toolchain from discovered / extracted / user path     │
│      ▸ materializes each entry under source.repos: (with defaults            │
│        when entries are absent):                                             │
│          • Linux_for_Tegra (overlay tracker)                                 │
│              default → git init empty at                                     │
│                        <source.root_path>/Linux_for_Tegra/                   │
│              override → git clone from profile's url/ref (+ subdir)          │
│          • bsp_sources (kernel-source baseline)                       │
│              default → source_sync.sh -d <source.root_path>/bsp_sources   │
│                        -t jetson_<major.minor>  (NVIDIA upstream;            │
│                        repos+sub-paths read from source_sync.sh)             │
│              override → git clone customer repo, mount its               │
│                        canonical kernel-side sub-paths under                 │
│                        <source.root_path>/bsp_sources/                    │
│          • any other entries → cloned alongside per their url/path           │
│                                                                              │
│   /jetson-link-docs   (optional)                                             │
│      ▸ register pre-downloaded docs (BSP developer guide, design guide,      │
│        datasheet, pinmux spreadsheet, EEPROM layout) in the profile's        │
│        `documents:` block                                                    │
│      ▸ files must already exist under <documents.root_path>/                 │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ CUSTOMIZE (per "customize-*" invocation)                                     │
│                                                                              │
│   Prerequisites: /jetson-generate-kb (refresh KB anytime) and, for custom    │
│   carriers on first run, /jetson-derive-carrier.                             │
│                                                                              │
│   1. git pull every shared repo.                                             │
│   2. customize-* identifies file(s) to change; routes by owning repo:        │
│                                                                              │
│   ┌───────────────────────────────┐    ┌──────────────────────────────────┐  │
│   │ A. Linux_for_Tegra overlay    │    │ B. Source repo (bsp_sources/, or │  │
│   │    (sparse, file-level)       │    │    customer kernel repo, or any  │  │
│   │                               │    │    extras under source.repos:)   │  │
│   │ At most TWO batched commits   │    │                                  │  │
│   │ per §Commit batching:         │    │ ▸ edit in place — clone HEAD is  │  │
│   │  • pristine import (files     │    │   the pristine baseline; no copy │  │
│   │    not yet imported)          │    │   needed.                        │  │
│   │  • customization              │    │ ▸ §Preview gate on diff.         │  │
│   │ Both pass through §Commit     │    │ ▸ accept: add + commit + push.   │  │
│   │ message preview gate.         │    │ ▸ reject: git checkout -- <f>.   │  │
│   └───────────────┬───────────────┘    └────────────────┬─────────────────┘  │
│                   ▼                                     ▼ (auto-chains to    │
│   Files committed in the overlay.                          Build if accepted)│
│   No build needed. bsp_image UNCHANGED.                                      │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ BUILD BSP SOURCE (auto-chained from Customize when source repos changed)     │
│                                                                              │
│   Skipped when Customize only touched the Linux_for_Tegra overlay.           │
│   Re-runnable on demand via /jetson-build-source.                            │
│                                                                              │
│   1. Identify dirty source repos under <source.root_path>/bsp_sources/ via   │
│      watermark file <source.root_path>/.build-state.yaml.                    │
│   2. Pick build mode by dirty set (or argument: dt | oot | kernel | full).   │
│      Drives NVIDIA's Linux_for_Tegra/source/Makefile + kernel/Makefile;      │
│      uses source.toolchain as CROSS_COMPILE.                                 │
│   3. Build outputs stay IN-TREE under bsp_sources/ — NOT staged into the     │
│      overlay. Write trace-to-dirty manifest at                               │
│      <source.root_path>/.build-manifest.yaml listing each rebuilt artifact   │
│      traceable to a dirty source repo (manifest schema lives in              │
│      /jetson-build-source).                                                  │
│                                                                              │
│   Outcome: build artifacts in-tree at bsp_sources/, manifest written.        │
│            Linux_for_Tegra overlay UNCHANGED. bsp_image UNCHANGED.           │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ DEPLOY — PROMOTE → FLASH → VALIDATE  (three skills, independently invokable) │
│                                                                              │
│   ┌─────────────────────┐    ┌────────────────────┐    ┌────────────────┐    │
│   │ /jetson-promote-    │───►│ /jetson-flash-     │───►│ /jetson-       │    │
│   │     image           │    │     image          │    │  validate-image│    │
│   │  TWO channels →     │    │  flash to device   │    │   static +     │    │
│   │     bsp_image       │    │                    │    │   on-target    │    │
│   └──────────┬──────────┘    └──────────┬─────────┘    └────────┬───────┘    │
│              ▼                          ▼                       ▼            │
│   ┌─────────────────────┐    ┌────────────────────┐    ┌────────────────┐    │
│   │ Channel A — OVERLAY │    │ cd                 │    │ run validation │    │
│   │ 1. git fetch        │    │   <bsp_image.      │    │ against staged │    │
│   │    overlay; refuse  │    │     root_path>/    │    │ artifacts and/ │    │
│   │    if origin has    │    │     Linux_for_Tegra│    │ or the just-   │    │
│   │    unpulled commits │    │ sudo ./flash.sh    │    │ flashed device │    │
│   │ 2. for each tracked │    │   [-k <partition>] │    │                │    │
│   │    file at overlay  │    │   <board>          │    │                │    │
│   │    HEAD: cp into    │    │   <boot-dev>       │    │                │    │
│   │    bsp_image,       │    │                    │    │                │    │
│   │    diff-aware, sudo │    │ DUT in RCM mode    │    │                │    │
│   │    cp -p for        │    │                    │    │                │    │
│   │    rootfs/* only.   │    │                    │    │                │    │
│   │                     │    │                    │    │                │    │
│   │ Channel B — BUILD   │    │                    │    │                │    │
│   │ MANIFEST            │    │                    │    │                │    │
│   │ 3. read .build-     │    │                    │    │                │    │
│   │    manifest.yaml;   │    │                    │    │                │    │
│   │    for each entry,  │    │                    │    │                │    │
│   │    cp src → dst,    │    │                    │    │                │    │
│   │    same diff-aware  │    │                    │    │                │    │
│   │    logic. Channels  │    │                    │    │                │    │
│   │    are disjoint by  │    │                    │    │                │    │
│   │    construction;    │    │                    │    │                │    │
│   │    on rare overlap, │    │                    │    │                │    │
│   │    manifest wins.   │    │                    │    │                │    │
│   └─────────────────────┘    └────────────────────┘    └────────────────┘    │
│                                                                              │
│   Typical chain: promote → flash → validate. Each skill is also runnable     │
│   on its own — e.g. re-flash without re-promoting, or re-validate without    │
│   re-flashing.                                                               │
│                                                                              │
│   Note: ordinary git operations on the shared repos have NO bsp_image /      │
│         device side effect. After jetson-init-image prepares the image, only    │
│         the three Deploy skills touch bsp_image and the device.             │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Path resolution (workspace convention)

The workspace root is **discovered** at load time as the parent of
the active profile's `target-platform/` directory — never recorded
in the profile, so the project is portable across hosts. Three
optional override fields layer on top:

| Variable | Default | Override field in profile |
|---|---|---|
| `<bsp_image.root_path>` | `<workspace>/Image` | `bsp_image.root_path` |
| `<source.root_path>` | `<workspace>/Source` | `source.root_path` (entire `source:` block written only when overriding) |
| `<documents.root_path>` | `<workspace>/Documents` | `documents.root_path` |

`<bsp_image.version>` is auto-derived (`<DERIVED>`) by
`jetson-init-image` from the BSP tarball filename
(`Jetson_Linux_R<ver>_aarch64.tbz2`) or `nv_tegra_release` at
`<bsp_image.root_path>/Linux_for_Tegra/`. It's a snapshot — re-run
`jetson-init-image` after extracting a new BSP to refresh.

See [`platform_template.yaml`](../references/platform_template.yaml)
for the full schema and field markers.

---

## Skill inventory

| Phase | Skill | Role |
|---|---|---|
| Setup | `jetson-quick-start` | entrypoint: choose setup mode, ask one core questionnaire, and pass `quick_start_prefill` to downstream setup skills |
| Setup | `jetson-init-target` | author + activate a new profile (`reference_devkit:` plus optional `custom_carrier:`) |
| Setup | `jetson-set-target` | switch the active pointer among already-authored profiles |
| Setup | `jetson-download-bsp` | Auto Setup helper: fetch BSP/rootfs tarballs, `public_sources.tbz2`, `x-tools.tbz2`, and release docs into the workspace |
| Setup | `jetson-init-image` | extract BSP tarballs, run `apply_binaries.sh`, and write `bsp_image:` |
| Setup | `jetson-init-source` | `git init` the empty Linux_for_Tegra overlay tracker, `git clone` the shared repos, ensure kernel sources are sync'd |
| Setup | `jetson-link-docs` | register paths to pre-downloaded target documents (BSP developer guide, design guide, datasheet, pinmux spreadsheet, etc.) in the profile's `documents:` block |
| Customize (helper) | `jetson-generate-kb` | scan BSP + sources and produce `target-platform/<profile-stem>.md`; re-runnable anytime to refresh (also a prerequisite for `jetson-derive-carrier` — KB locates the carrier-specific files to fork) |
| Customize (first run) | `jetson-derive-carrier` | (custom carriers only) derive the custom carrier's flash conf + supporting files (pinmux, padvoltage, GPIO, EEPROM, board.cfg, kernel board DTS) from the reference devkit; re-runnable against a new reference BSP |
| Customize | `jetson-customize-clocks` | BPMP DTB `max-rate-custom` + `nvpower.sh` cpufreq / devfreq |
| Customize | `jetson-customize-nvpmodel` | per-board `nvpmodel/<board>.conf` |
| Customize | `jetson-customize-fan` | per-board `nvfancontrol/<board>.conf` |
| Customize | `jetson-optimize-memory` | reclaim DRAM via MB1 BCT carveouts, MB2 BCT cluster + AST, kernel reserved-memory, SWIOTLB |
| Build | `jetson-build-source` | auto-chained after Customize when source repos changed; rebuilds dirty source repos (modes: dt/oot/kernel/full) and writes `<source.root_path>/.build-manifest.yaml` — does NOT stage into the overlay |
| Deploy | `jetson-promote-image` | copy overlay → `bsp_image` after pre-promote collision check |
| Deploy | `jetson-flash-image` | invoke `flash.sh` / `l4t_initrd_flash.sh` from `bsp_image` |
| Deploy | `jetson-validate-image` | static + on-target validation against the just-flashed DUT |

---

## Phase semantics (cheat sheet)

| Property | Setup | Customize | Build | Deploy |
|---|---|---|---|---|
| Trigger | explicit | explicit (per customize-*) | auto-chained from Customize (or explicit `/jetson-build-source`) | explicit per leg |
| User-acceptance gate? | n/a | yes, on every source-side or overlay-side diff | no — build success is the implicit accept | n/a (each leg does its own job) |
| Touches `bsp_image`? | yes — `jetson-init-image` prepares it | no | no | yes — promote / flash / validate |
| Touches the device? | no | no | no | yes — only in `jetson-flash-image` and `jetson-validate-image` |
| Multi-user sync? | `git pull` after clone | `git pull` at start of every invocation | inherits Customize sync; commits + pushes binaries | pre-promote collision check refuses if origin has unpulled commits |

---

## Decisions locked in

| Topic | Decision |
|---|---|
| Shared repos | multi-user git repos: `Linux_for_Tegra/` overlay tracker + kernel-source baseline (default: NVIDIA repos cloned by `source_sync.sh`; override: customer kernel repo) + any extras under the active profile's `source.repos:` map. Names and counts are open-ended — `source_sync.sh`'s `SOURCE_INFO` is the canonical source for the NVIDIA default set. |
| Customize routing | Overlay files → pristine + customization commits (sparse mirror); source-repo files → edit in place (full clone) |
| Build trigger | Auto-chains from Customize when a source repo is touched; manual re-run via `/jetson-build-source` |
| Build acceptance gate | None on binary stage — build success is the implicit accept |
| Deploy structure | Three independently invokable skills: promote → flash → validate |
| Multi-user collisions | Pre-promote check in `/jetson-promote-image` refuses if overlay origin has unpulled commits |
| Workspace path convention | Defaults: `<workspace>/{Image,Source,Documents}`. Overrides: `bsp_image.root_path`, `source.root_path`, `documents.root_path` in profile. `<workspace>` discovered at load time, never recorded. |
| Skill naming | All kebab-case |

---

## References

- [`../references/platform_template.yaml`](../references/platform_template.yaml)
  — schema for the target-platform profile YAML.
- Per-skill `SKILL.md` files under `../skills/` for procedural
  detail.
