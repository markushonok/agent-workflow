#!/bin/bash
# Generic replaceable agent boundary: run one executable in a working directory.
set -eu

runner=$1
workspace=$2
prompt=$3

[ -x "$runner" ] || { printf 'Agent is not executable: %s\n' "$runner" >&2; exit 2; }

cd "$workspace" || { printf 'Cannot enter workspace: %s\n' "$workspace" >&2; exit 2; }

exec "$runner" --workspace "$workspace" --prompt "$prompt"