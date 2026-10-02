#!/bin/bash
# Compatible runner: records actual ledger operations, not fabricated result JSON.
set -eu
[ "$1" = --workspace ] && [ "$3" = --prompt ]
prompt=$4
tool=$REVIEW_LEDGER_TOOL
ledger=$REVIEW_LEDGER
control=$TEST_CONTROL
"$tool" json "$ledger" > "$ledger.initial"
role=$(jq -j .dimension "$ledger.initial")
"$tool" help > "$control/$role.help"
cp "$ledger.initial" "$control/$role.initial"
cp "$prompt" "$control/$role.prompt"
pwd -P > "$control/$role.cwd"
printf 'diagnostic-%s\n' "$role" >&2
touch "$control/$role.ready"
if jq -e '.barrier == true' "$control/config" >/dev/null; then
  attempts=0
  until [ -f "$control/design.ready" ] && [ -f "$control/behavior.ready" ]; do
    attempts=$((attempts+1))
    [ "$attempts" -lt 2000 ] || exit 9
    sleep 0.01
  done
fi
if jq -e --arg role "$role" '.fail == $role' "$control/config" >/dev/null; then exit 9; fi
if jq -e --arg role "$role" '.forged_output == $role' "$control/config" >/dev/null; then
  printf '{"status":"completed","findings":[]}\n'
  exit 0
fi
rule=$(jq -j '.rules[0] // ""' "$ledger.initial")
jq -j '.changed_files[] | . + "\u0000"' "$ledger.initial" > "$ledger.paths"
while IFS= read -r -d '' file; do
  if jq -e --arg role "$role" '.skip_cover == $role' "$control/config" >/dev/null; then break; fi
  if [ "$role" = design ]; then "$tool" cover "$ledger" "$file" "$rule"
  else "$tool" cover "$ledger" "$file"; fi
done < "$ledger.paths"
if jq -e '.findings == true' "$control/config" >/dev/null; then
  file=$(jq -j '.changed_files[0]' "$ledger.initial")
  if [ "$role" = design ]; then
    "$tool" finding "$ledger" "$file" "$rule" 'Rule#Provision' 'Correction with "quotes"'
  else
    "$tool" finding "$ledger" "$file" 'Result retrieval' 'Out-of-range input' 'Reject input' 'Returns success' 'Contradicts contract'
  fi
fi
if jq -e --arg role "$role" '.skip_finalize == $role' "$control/config" >/dev/null; then exit 0; fi
"$tool" finalize "$ledger" > "$control/$role.finalize-output"
[ ! -s "$control/$role.finalize-output" ]
"$tool" json "$ledger" > "$control/$role.result"
if jq -e --arg role "$role" '.fail_after_finalize == $role' "$control/config" >/dev/null; then exit 9; fi
# Agent stdout is opaque and must never become the specialized result.
printf 'Review complete. This prose is not JSON.\n'