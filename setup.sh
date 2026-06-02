#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup.sh --workspace <path> [--force]

Populate <workspace>/.claude/ with the Jetson BSP customization skills,
context, and references from this repo so Claude Code can pick them up
when launched in <workspace>.

Required:
  --workspace <path>  target workspace directory; <path>/.claude/ will
                      be created.

Optional:
  --force             remove an existing <path>/.claude/ before
                      rebuilding. Without --force the script refuses
                      to overwrite an existing directory.
  -h, --help          show this message.
EOF
}

workspace=""
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      [[ $# -ge 2 ]] || { echo "setup.sh: --workspace requires a value" >&2; exit 2; }
      workspace="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "setup.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$workspace" ]]; then
  echo "setup.sh: --workspace is required" >&2
  usage >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$repo_root/skills" ]]; then
  echo "setup.sh: $repo_root/skills not found — run from the cloned repo root" >&2
  exit 1
fi

claude_dir="$workspace/.claude"

if [[ -e "$claude_dir" ]]; then
  if [[ "$force" -eq 1 ]]; then
    echo "setup.sh: removing existing $claude_dir"
    rm -rf "$claude_dir"
  else
    echo "setup.sh: $claude_dir already exists — re-run with --force to rebuild" >&2
    exit 1
  fi
fi

mkdir -p "$claude_dir/skills"

# Copy each top-level content directory into the workspace's .claude/.
for entry in skills context references; do
  if [[ -d "$repo_root/$entry" ]]; then
    cp -r "$repo_root/$entry" "$claude_dir/"
  fi
done

# Drop any .gitkeep placeholders carried over from empty skill dirs.
find "$claude_dir/skills" -type f -name '.gitkeep' -delete

echo "setup.sh: workspace ready at $workspace"
echo "setup.sh: next step → cd $workspace && claude"
