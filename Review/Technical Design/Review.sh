#!/bin/bash
# WORKTREE AGENT TASK_OR_EMPTY RULE_PATTERN [RULE_PATTERN ...]
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -ge 4 ] || { printf 'Technical Design needs WORKTREE AGENT TASK_OR_EMPTY RULE_PATTERN...\n' >&2; exit 2; }
worktree=$1; agent=$2; task=$3; shift 3
[ -f "$agent" ] && [ -x "$agent" ] || exit 2
agent="$(CDPATH= cd -- "$(dirname -- "$agent")" && pwd)/$(basename -- "$agent")"
if [ -n "$task" ]; then
  [ -f "$task" ] && [ -r "$task" ] || { printf 'Unreadable task: %s\n' "$task" >&2; exit 2; }
  task="$(CDPATH= cd -- "$(dirname -- "$task")" && pwd)/$(basename -- "$task")"
fi
worktree=$(CDPATH= cd -- "$worktree" && pwd) || exit 2
temporary=$(mktemp -d "${TMPDIR:-/tmp}/design-review.XXXXXX") || exit 2
trap 'rm -rf -- "$temporary"' EXIT
trap 'exit 2' INT TERM
: > "$temporary/rules"
# Quoted CLI patterns expand deliberately here, relative to the reviewed worktree.
for pattern in "$@"; do
  (CDPATH= cd -- "$worktree" && compgen -G "$pattern") > "$temporary/matches" || {
    printf 'Rule pattern has no matches: %s\n' "$pattern" >&2; exit 2;
  }
  while IFS= read -r path; do
    case "$path" in /*|[A-Za-z]:/*) ;; *) path="$worktree/$path" ;; esac
    [ -f "$path" ] && [ -r "$path" ] || { printf 'Unreadable rule: %s\n' "$path" >&2; exit 2; }
    printf '%s/%s\n' "$(CDPATH= cd -- "$(dirname -- "$path")" && pwd)" "$(basename -- "$path")" >> "$temporary/rules"
  done < "$temporary/matches"
done
LC_ALL=C sort -u "$temporary/rules" > "$temporary/ordered-rules"
set -- "$temporary/ledger" "$worktree" design
while IFS= read -r rule; do set -- "$@" "$rule"; done < "$temporary/ordered-rules"
/bin/bash "$root/Ledger.sh" init "$@"
{
  cat "$root/Technical Design/Prompt.md"
  printf '\n# Authoritative engineering rule files\n\n'
  cat "$temporary/ordered-rules"
  if [ -n "$task" ]; then printf '\nTask context: %s\n' "$task"; fi
  printf '\nLedger tool: %s\nLedger state: %s\n' "$root/Ledger.sh" "$temporary/ledger"
  printf 'Use "$REVIEW_LEDGER_TOOL" help, then pass "$REVIEW_LEDGER" as the ledger argument.\n'
} > "$temporary/prompt"
if ! REVIEW_LEDGER_TOOL="$root/Ledger.sh" REVIEW_LEDGER="$temporary/ledger" \
  /bin/bash "$root/../Agents/Run.sh" "$agent" "$worktree" "$temporary/prompt" >/dev/null; then
  printf 'Technical Design agent execution failed\n' >&2; exit 2
fi
/bin/bash "$root/Ledger.sh" json "$temporary/ledger" > "$temporary/result" || exit 2
jq -e -s -L "$root" 'include "Technical Design/Validate"; length == 1 and (.[0] | design_valid)' "$temporary/result" >/dev/null || {
  printf 'Technical Design agent did not finalize its ledger\n' >&2; exit 2;
}
cat "$temporary/result"