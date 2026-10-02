#!/bin/bash
# WORKTREE AGENT TASK_OR_EMPTY
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -eq 3 ] || { printf 'Behavior needs WORKTREE AGENT TASK_OR_EMPTY\n' >&2; exit 2; }
worktree=$1; agent=$2; task=$3
[ -f "$agent" ] && [ -x "$agent" ] || exit 2
agent="$(CDPATH= cd -- "$(dirname -- "$agent")" && pwd)/$(basename -- "$agent")"
worktree=$(CDPATH= cd -- "$worktree" && pwd) || exit 2
if [ -n "$task" ]; then
  [ -f "$task" ] && [ -r "$task" ] || { printf 'Unreadable task: %s\n' "$task" >&2; exit 2; }
  task="$(CDPATH= cd -- "$(dirname -- "$task")" && pwd)/$(basename -- "$task")"
fi
temporary=$(mktemp -d "${TMPDIR:-/tmp}/behavior-review.XXXXXX") || exit 2
trap 'rm -rf -- "$temporary"' EXIT
trap 'exit 2' INT TERM
/bin/bash "$root/Ledger.sh" init "$temporary/ledger" "$worktree" behavior
{
  cat "$root/Behavior/Prompt.md"
  if [ -n "$task" ]; then printf '\nTask context: %s\n' "$task"; fi
  printf '\nLedger tool: %s\nLedger state: %s\n' "$root/Ledger.sh" "$temporary/ledger"
  printf 'Use "$REVIEW_LEDGER_TOOL" help, then pass "$REVIEW_LEDGER" as the ledger argument.\n'
} > "$temporary/prompt"
if ! REVIEW_LEDGER_TOOL="$root/Ledger.sh" REVIEW_LEDGER="$temporary/ledger" \
  /bin/bash "$root/../Agents/Run.sh" "$agent" "$worktree" "$temporary/prompt" >/dev/null; then
  printf 'Behavior agent execution failed\n' >&2; exit 2
fi
/bin/bash "$root/Ledger.sh" json "$temporary/ledger" > "$temporary/result" || exit 2
jq -e -s -L "$root" 'include "Behavior/Validate"; length == 1 and (.[0] | behavior_valid)' "$temporary/result" >/dev/null || {
  printf 'Behavior agent did not finalize its ledger\n' >&2; exit 2;
}
cat "$temporary/result"