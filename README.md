# Agentic Skills for Jetson BSP Customization

This repository contains Claude Code skills for setting up and
customizing an NVIDIA Jetson Linux Board Support Package (BSP).

The goal is to let an engineer work from a normal project workspace:
pick a Jetson target, prepare the BSP image and sources, make BSP
customizations through guided skills, then promote, flash, and validate
the result.

This project is currently not accepting contributions.

## Disclaimer

These skills help automate Jetson BSP setup and customization, but they
do not replace NVIDIA official documentation or engineering review.
Review generated plans, commands, diffs, and commit messages before
accepting them. Flashing can erase device storage or leave a target
temporarily unbootable, so keep backups and verify the active target,
BSP release, and hardware setup before deploy steps.

## What This Repo Provides

This repo is a skill bundle. It does not contain a Jetson BSP image,
source tarballs, or board documents. Instead, it installs instructions,
templates, and helper references into a workspace so Claude Code can
guide the BSP workflow.

The skills cover four broad stages:

| Stage | What happens |
|---|---|
| Setup | Create/select the active target, download or register BSP inputs, extract the image, initialize sources, and link documents. |
| Customize | Apply BSP changes such as pinmux, USB, PCIe, UPHY, clocks, fan, nvpmodel, camera, MGBE, or memory tuning. |
| Build | Rebuild source-side artifacts when a customization changed kernel-side sources. |
| Deploy | Promote workspace changes into the BSP image, flash the device, and validate the result. |

## Skills at a Glance

| Type | Skill | One-line introduction |
|---|---|---|
| Setup | `/jetson-quick-start` | Starts the setup flow, asks the core questions, and dispatches the right setup skills. |
| Setup | `/jetson-init-target` | Creates a target-platform profile and updates the active target pointer. |
| Setup | `/jetson-set-target` | Switches the active target pointer to an existing profile. |
| Setup | `/jetson-download-bsp` | Downloads Jetson Linux BSP artifacts for the Auto Setup path. |
| Setup | `/jetson-init-image` | Extracts the BSP image, applies binaries, and records the image path. |
| Setup | `/jetson-init-source` | Initializes the source workspace, overlay tracker, BSP sources, and toolchain. |
| Setup | `/jetson-link-docs` | Registers local Jetson reference documents in the active profile. |
| Setup | `/jetson-generate-kb` | Builds a per-target markdown knowledge base from the prepared workspace. |
| Customization | `/jetson-derive-carrier` | Forks reference carrier files and scaffolds a custom-carrier overlay. |
| Customization | `/jetson-customize-pinmux` | Edits pinmux DTSI for SoC pin function, direction, and pull settings. |
| Customization | `/jetson-customize-usb` | Enables or disables Jetson USB2/USB3 SS ports via kernel-DT overlay. |
| Customization | `/jetson-customize-pcie` | Configures PCIe controller mode and link speed on the carrier. |
| Customization | `/jetson-customize-uphy` | Allocates UPHY lanes across PCIe/USB3/MGBE on custom carriers. |
| Customization | `/jetson-customize-mgbe` | Configures MGBE Ethernet controller, PHY, and MAC settings. |
| Customization | `/jetson-customize-camera` | Edits camera device tree overlays for CSI sensors and tegra-camera-platform. |
| Customization | `/jetson-customize-clocks` | Edits BSP-side clock, DVFS, governor, and BPMP DTB settings. |
| Customization | `/jetson-customize-fan` | Edits nvfancontrol profiles, curves, governors, and boot defaults. |
| Customization | `/jetson-customize-nvpmodel` | Edits nvpmodel power modes, clamps, and boot defaults. |
| Customization | `/jetson-optimize-memory` | Reclaims DRAM by disabling or resizing unused reserved-memory consumers. |
| Build | `/jetson-build-source` | Rebuilds DTBs, modules, or kernel artifacts from source-side changes. |
| Deploy | `/jetson-promote-image` | Stages customized overlay files and build outputs into the BSP image. |
| Deploy | `/jetson-flash-image` | Flashes a promoted BSP image to a Jetson DUT in recovery mode. |
| Deploy | `/jetson-validate-image` | Runs static BSP checks and on-target validation after flashing. |
| Inspection | `/jetson-print-bsp-info` | Prints a quick host-side summary of a Linux_for_Tegra BSP tree. |

## Install the Skills Into a Workspace

Clone this repository:

```sh
git clone https://github.com/NVIDIA-AI-IOT/jetson-bsp-skills.git
cd jetson-bsp-skills
```

Install the skills into a workspace:

```sh
./setup.sh --workspace <workspace>
```

Then start Claude Code from that workspace:

```sh
cd <workspace>
claude
```

Inside Claude Code, ask:

```text
help me setup the bsp customization workspace
```

This should start `/jetson-quick-start`, the recommended entry point
for new users and the easiest way to choose the right setup mode.

## Typical First Run

For a new user, the normal path is:

1. Install this skill bundle with `setup.sh`.
2. Start Claude Code from the workspace.
3. Ask `help me setup the bsp customization workspace`.
4. Choose `Auto Setup` for a fresh workspace, or `Guided Setup` if you
   already downloaded BSP inputs.
5. Answer the platform, BSP release, and custom-carrier questions.
6. Let quick-start run the setup chain.
7. If using a custom carrier, run or allow `/jetson-derive-carrier`
   before customization skills.
8. Run the needed `/jetson-customize-*` skill.
9. Run `/jetson-promote-image`, `/jetson-flash-image`, and
    `/jetson-validate-image` when ready to deploy.

## License

This code is dual-licensed with documentation under the CC-BY-4.0 AND source code under Apache-2.0 license terms. See [LICENSE](LICENSE).
