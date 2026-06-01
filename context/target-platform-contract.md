# Target Platform Contract

The load-time contract every Jetson / IGX customization skill follows
to consume the active target.

## Read-order contract

Every skill that touches the target platform **must** follow this
sequence before doing anything else — skipping it risks silently
applying the change to (or missing it from) the wrong target.

1. Read `target-platform/active_target.yml` (runtime-owned, lives in `<workspace>/target-platform/`, not in this repo).
2. If `active` is `NA` or names a file that does not exist in
   `target-platform/`, **refuse** and route the user to
   `jetson-set-target` (existing profiles) or
   `jetson-init-target` (no profiles yet).
3. Load `target-platform/<active>.yaml`.
4. Use only values from that file. Treat any field set to `NA` as
   missing — refuse if the requested edit needs it.

If the user names a target that disagrees with the active profile:

| Operation | Allowed? |
|---|---|
| Read-only query (e.g. "which BPMP DTB does AGX Thor use?") — resolve from the named profile or catalogue, don't touch `active_target.yml` | Yes |
| Mutating (edit, build, promote, flash, validate) — refuse and ask the user to switch via `/jetson-set-target` | No |

## Profile shape — `target-platform/<name>.yaml`

- **Case 1 (reference devkit)** — `reference_devkit` only.
- **Case 2 (custom carrier)** — `reference_devkit` (closest NVIDIA
  devkit baseline) + `custom_carrier` (the customer target).

| Block | Always present? |
|---|---|
| `reference_devkit` | Yes |
| `custom_carrier` | Only in Case 2 |
| `bsp_image` | After `/jetson-init-image` (`version` derived; `root_path` only when overriding) |
| `source` | Only when overriding `<workspace>/Source` |
| `documents` | Only when the user opts in |

See [`platform_template.yaml`](../references/platform_template.yaml)
for the full schema and worked examples.

**To capture a new target**: run `/jetson-init-target` to author and
activate `reference_devkit:` plus optional `custom_carrier:`, then run
`/jetson-init-image` to extract the BSP and add `bsp_image:`. A freshly
created profile may be partial until Setup completes.

## Workspace path resolution

`<workspace>` = parent of the active profile's `target-platform/`
directory. Discovered at load time; not stored in the profile (tree
stays portable). Overrides resolve against it:

| Override field | Default |
|---|---|
| `bsp_image.root_path` | `<workspace>/Image` |
| `source.root_path`    | `<workspace>/Source` |
| `documents.root_path` | `<workspace>/Documents` |

Note: the entire `source:` block is omitted from the profile when
`source.root_path` equals the default.

`documents.*` per-document fields (e.g. `bsp_developer_guide`) are
paths **relative** to `<documents.root_path>/` and may include
subfolders.

## Derived platform facts

Do not store these facts in the profile. Every skill derives them from
the active profile's `reference_devkit` / `custom_carrier` identifiers
and, when needed, the platform catalogue.

| SoC generation | Product family | GPU driver stack | `apply_binaries.sh` flag |
|---|---|---|---|
| T234 | Orin / IGX Orin | nvgpu | none |
| T264 and later | Thor and newer | OpenRM | `--openrm` when the BSP supports it |

Use this GPU-driver invariant before edits, builds, promotion, flashing,
or validation. Do not infer the stack from directory names, BSP release
numbers, or missing files unless you are only validating an already
extracted image against the platform-derived expectation. If the active
platform and BSP release imply different GPU stacks, stop before side
effects, warn the user, and ask for a concrete correction or explicit
override. If the SoC generation is unknown, refuse rather than guessing.

## Active-pointer mechanics — `target-platform/active_target.yml`

Single-line pointer file: `active: <filename>.yaml` (bare filename of
a sibling in `target-platform/`), or `active: NA` when none is
selected. Switching targets is a one-field edit, typically via
`/jetson-set-target`.
