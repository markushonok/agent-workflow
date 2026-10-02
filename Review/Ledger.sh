#!/bin/bash
# One reviewer owns one ledger. All mutations and serialization use jq.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command=${1:-help}
shift || :
if [ "$command" = help ]; then
  cat <<'HELP'
Ledger.sh help
Ledger.sh init LEDGER WORKTREE design RULE_FILE [RULE_FILE ...]
Ledger.sh init LEDGER WORKTREE behavior
Ledger.sh status LEDGER
Ledger.sh json LEDGER
Ledger.sh cover LEDGER CHANGED_FILE [RULE_FILE ...]
Ledger.sh finding LEDGER CHANGED_FILE RULE_FILE PROVISION DESCRIPTION  (design)
Ledger.sh finding LEDGER CHANGED_FILE AREA SCENARIO EXPECTED ACTUAL EXPLANATION  (behavior)
Ledger.sh finalize LEDGER

status   human-readable review progress
json     current complete ledger state as JSON, including before finalization; read-only
finalize validate completeness and consistency and mark the review finalized; no stdout

Use repository-relative changed filenames from json.changed_files, including deleted files.
Design rule arguments must exactly match authoritative paths from json.rules.
Cover each file, recording only applicable rules. Zero applicable rules is allowed.
Findings require a known changed file; design findings require a rule recorded by cover.
Mutations reset finalized. Finalize fails until every file is covered and state is valid.
Json only parses the ledger; it does not enforce coverage or completion constraints.
Never edit the ledger directly.
HELP
  exit 0
fi
[ "$#" -gt 0 ] || { printf 'Ledger path required; run Ledger.sh help\n' >&2; exit 2; }
ledger=$1; shift
if [ "$command" = json ]; then
  [ "$#" -eq 0 ] || { printf 'Json takes only a ledger\n' >&2; exit 2; }
  exec jq -e -s 'if length == 1 and (.[0] | type == "object") then .[0] else error("Expected one ledger object") end' "$ledger"
fi
temporary="$ledger.tmp"
trap 'rm -f -- "$temporary"' EXIT
invalid() { printf '%s\n' "$1" >&2; exit 2; }
validate() {
  jq -e -s -L "$root" 'include "Ledger"; length == 1 and (.[0] | ledger_valid)' "$1" >/dev/null
}
if [ "$command" = init ]; then
  [ "$#" -ge 2 ] || invalid 'Init needs worktree and dimension'
  worktree=$1; dimension=$2; shift 2
  case "$dimension" in design) [ "$#" -gt 0 ] || invalid 'Design needs normative rule files' ;; behavior) [ "$#" -eq 0 ] || invalid 'Behavior does not accept rules' ;; *) invalid 'Unknown dimension' ;; esac
  rules='[]'
  for rule in "$@"; do
    [ -f "$rule" ] && [ -r "$rule" ] || invalid "Unreadable rule: $rule"
    rules=$(jq -n --argjson rules "$rules" --arg rule "$rule" '$rules + [$rule] | unique')
  done
  git -C "$worktree" rev-parse --verify 'HEAD^{commit}' >/dev/null
  # Union staged, unstaged and non-ignored untracked paths; NULs preserve spaces/newlines.
  { git -C "$worktree" diff --cached --name-only -z --no-renames HEAD -- &&
    git -C "$worktree" diff --name-only -z --no-renames -- &&
    git -C "$worktree" ls-files --others --exclude-standard -z; } > "$temporary"
  jq -Rs --arg dimension "$dimension" --argjson rules "$rules" \
    'split("\u0000") | map(select(length>0)) | unique | . as $files |
      {dimension:$dimension,finalized:false,rules:$rules,findings:[],changed_files:$files,
       files:($files | map({key:.,value:(if $dimension=="design" then {covered:false,rules:[]} else {covered:false} end)}) | from_entries)}' "$temporary" > "$ledger"
  validate "$ledger" || invalid 'Invalid initial ledger'
  exit 0
fi
validate "$ledger" || invalid 'Malformed or inconsistent ledger'
case "$command" in
  status)
    [ "$#" -eq 0 ] || invalid 'Status takes only a ledger'
    jq -r '"Dimension: \(.dimension)\nFinalized: \(.finalized)\nCoverage: \([.files[] | select(.covered)] | length)/\(.files | length)\nFindings: \(.findings | length)",
      (.files | to_entries[] | select(.value.covered == false) | "Uncovered: \(.key)")' "$ledger" ;;
  cover)
    [ "$#" -ge 1 ] || invalid 'Cover needs a changed file'
    file=$1; shift
    rules='[]'
    for rule in "$@"; do rules=$(jq -n --argjson rules "$rules" --arg rule "$rule" '$rules + [$rule] | unique'); done
    jq -e --arg file "$file" --argjson rules "$rules" '
      if (.files | has($file)) then
        if .dimension == "design" then
          .rules as $allowed | if all($rules[]; . as $r | $allowed | index($r) != null) then
            .files[$file] = {covered:true,rules:((.files[$file].rules + $rules)|unique)}
          else error("Unknown normative rule") end
        elif $rules == [] then .files[$file].covered = true
        else error("Behavior coverage takes no rules") end | .finalized = false
      else error("Unknown changed file") end' "$ledger" > "$temporary" ;;
  finding)
    if jq -e '.dimension == "design"' "$ledger" >/dev/null; then
      [ "$#" -eq 4 ] || invalid 'Design finding needs FILE RULE PROVISION DESCRIPTION'
      jq --arg file "$1" --arg rule "$2" --arg provision "$3" --arg finding "$4" \
        '.findings += [{file:$file,rule:$rule,provision:$provision,finding:$finding}] | .finalized=false' "$ledger" > "$temporary"
    else
      [ "$#" -eq 6 ] || invalid 'Behavior finding needs FILE AREA SCENARIO EXPECTED ACTUAL EXPLANATION'
      jq --arg file "$1" --arg area "$2" --arg scenario "$3" --arg expected "$4" --arg actual "$5" --arg explanation "$6" \
        '.findings += [{file:$file,area:$area,scenario:$scenario,expected:$expected,actual:$actual,explanation:$explanation}] | .finalized=false' "$ledger" > "$temporary"
    fi ;;
  finalize)
    [ "$#" -eq 0 ] || invalid 'Finalize takes only a ledger'
    jq -e 'if all(.files[]; .covered == true) then .finalized=true else error("Uncovered changed files") end' "$ledger" > "$temporary" ;;
  *) invalid 'Unknown command; run Ledger.sh help' ;;
esac
if [ "$command" != status ]; then
  validate "$temporary" || invalid 'Invalid ledger operation'
  mv "$temporary" "$ledger"
fi