#!/bin/bash
# Run independent worktree reviews and mechanically aggregate their ledgers.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v git >/dev/null && command -v jq >/dev/null || exit 2
temporary=$(mktemp -d "${TMPDIR:-/tmp}/review.XXXXXX") || exit 2
trap 'rm -rf -- "$temporary"' EXIT
trap 'exit 2' INT TERM
: > "$temporary/patterns"
target= agent= task=

emit() {
  jq -e -s -L "$root" -f "$root/Validate.jq" "$temporary/result" > "$temporary/final" || exit 2
  cat "$temporary/final" || exit 2
  jq -e '.status == "completed"' "$temporary/final" >/dev/null || exit 2
  if jq -e '(.design.findings|length) + (.behavior.findings|length) > 0' "$temporary/final" >/dev/null; then exit 1; fi
  exit 0
}
configuration() {
  printf '%s\n' "$1" >&2
  jq -n --arg message "$1" '{status:"failed",error:{kind:"configuration",message:$message}} as $f |
    {status:"incomplete",design:$f,behavior:$f}' > "$temporary/result"
  emit
}
absolute_file() {
  [ -f "$1" ] && [ -r "$1" ] || return 2
  printf '%s/%s\n' "$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)" "$(basename -- "$1")"
}
while [ "$#" -gt 0 ]; do
  option=$1; shift
  case "$option" in
    --help|-h)
      printf '%s\n' 'Usage: review --target REPOSITORY --agent EXECUTABLE --rules PATTERN [--rules PATTERN ...] [--task FILE]' 'Relative rule patterns resolve from the worktree.' >&2
      exit 0 ;;
    --target|--agent|--rules|--task)
      [ "$#" -gt 0 ] || configuration "Missing value for $option"
      value=$1; shift
      case "$option" in
        --target) target=$value ;;
        --agent) agent=$value ;;
        --rules) printf '%s\0' "$value" >> "$temporary/patterns" ;;
        --task) task=$(absolute_file "$value") || configuration 'Task must be a readable file' ;;
      esac ;;
    *) configuration "Unknown argument: $option" ;;
  esac
done
[ -n "$target" ] && [ -n "$agent" ] && [ -s "$temporary/patterns" ] || configuration 'Required: --target, --agent, --rules'
target=$(CDPATH= cd -- "$target" && pwd) || configuration 'Invalid worktree directory'
agent=$(absolute_file "$agent") || configuration 'Agent must be a readable executable file'
[ -x "$agent" ] || configuration 'Agent must be executable'

# Only paths and ledgers are temporary; agents inspect the original stable worktree.
set -- "$target" "$agent" "$task"
while IFS= read -r -d '' pattern; do set -- "$@" "$pattern"; done < "$temporary/patterns"
/bin/bash "$root/Technical Design/Review.sh" "$@" > "$temporary/design" &
design_pid=$!
/bin/bash "$root/Behavior/Review.sh" "$target" "$agent" "$task" > "$temporary/behavior" &
behavior_pid=$!
design_status=0; behavior_status=0
wait "$design_pid" || design_status=$?
wait "$behavior_pid" || behavior_status=$?
for dimension in design behavior; do
  if [ "$dimension" = design ]; then code=$design_status; else code=$behavior_status; fi
  if [ "$code" -ne 0 ] || ! jq -e -s -L "$root" "include \"Technical Design/Validate\"; include \"Behavior/Validate\"; length == 1 and (.[0] | ${dimension}_valid)" "$temporary/$dimension" >/dev/null; then
    jq -n --arg dimension "$dimension" '{status:"failed",error:{kind:"review_failed",message:($dimension + " review did not finalize successfully")}}' > "$temporary/$dimension"
  fi
done
jq -n --slurpfile design "$temporary/design" --slurpfile behavior "$temporary/behavior" \
  '{status:(if $design[0].finalized == true and $behavior[0].finalized == true then "completed" else "incomplete" end),design:$design[0],behavior:$behavior[0]}' > "$temporary/result"
emit