#!/bin/bash
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
failed=0
setup() {
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/ledger test.XXXXXX")
  temporary=$(CDPATH= cd -- "$temporary" && pwd -P)
  trap 'rm -rf -- "$temporary"' EXIT
  repo="$temporary/repository with spaces"
  control="$temporary/control"
  mkdir -p "$repo/Engineering Rules" "$control"
  git -C "$repo" init -q --template=
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@localhost
  printf 'base\n' > "$repo/Staged.sh"
  printf 'base\n' > "$repo/Unstaged.sh"
  printf 'old\n' > "$repo/Deleted.sh"
  printf 'unchanged source\n' > "$repo/Caller.sh"
  printf '*.ignored\n' > "$repo/.gitignore"
  printf 'SPECIFICATION_MARKER\n' > "$repo/Engineering Rules/Composition.md"
  printf 'Second topic\n' > "$repo/Engineering Rules/Abstraction.md"
  git -C "$repo" add .
  git -C "$repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm Base
  printf 'staged\n' > "$repo/Staged.sh"
  git -C "$repo" add Staged.sh
  printf 'unstaged\n' > "$repo/Unstaged.sh"
  rm "$repo/Deleted.sh"
  printf 'new\n' > "$repo/Untracked file.sh"
  printf 'ignored cache\n' > "$repo/cache.ignored"
  task="$temporary/Task.md"
  printf 'TASK_MARKER\n' > "$task"
  rule="$repo/Engineering Rules/Composition.md"
  agent="$temporary/Compatible Agent.sh"
  cp "$ROOT/Tests/FakeRunner.sh" "$agent"
  chmod +x "$agent"
  export TEST_CONTROL="$control"
  printf '{}' > "$control/config"
  state="$temporary/ledger"
}
ledger() { /bin/bash "$ROOT/Review/Ledger.sh" "$@"; }
init_design() { ledger init "$state" "$repo" design "$rule"; }
cover_all() {
  ledger json "$state" | jq -j '.changed_files[] | . + "\u0000"' > "$temporary/paths"
  while IFS= read -r -d '' file; do ledger cover "$state" "$file" "$rule"; done < "$temporary/paths"
}
invoke() {
  printf '%s' "$1" > "$control/config"; shift
  set +e
  "$ROOT/Review/Review.sh" --target "$repo" --agent "$agent" --rules 'Engineering Rules/*.md' \
    --task "$task" "$@" > "$temporary/result" 2> "$temporary/diagnostics"
  code=$?
  set -e
  jq -e -s -L "$ROOT/Review" -f "$ROOT/Review/Validate.jq" "$temporary/result" >/dev/null
}
check() { jq -e "$1" "$temporary/result" >/dev/null; }
reject() { if "$@"; then printf 'Unexpected success\n' >&2; return 1; fi; }
test_init_and_help() {
  init_design
  jq -e '.changed_files == ["Deleted.sh","Staged.sh","Unstaged.sh","Untracked file.sh"] and all(.files[]; .covered == false and .rules == []) and .finalized == false' "$state" >/dev/null
  ledger help > "$temporary/help"
  for command in init status json cover finding finalize; do grep -q "Ledger.sh $command" "$temporary/help"; done
  reject ledger finalize "$state" > "$temporary/final" 2>/dev/null
  [ ! -s "$temporary/final" ]
}
test_json_and_status() {
  init_design
  cp "$state" "$temporary/before"
  ledger json "$state" > "$temporary/json"
  cmp "$state" "$temporary/before"
  jq -e -n --slurpfile s "$state" --slurpfile j "$temporary/json" '$s == $j and $j[0].finalized == false' >/dev/null
  ledger status "$state" > "$temporary/status"
  grep -q 'Coverage: 0/4' "$temporary/status"
  grep -q 'Findings: 0' "$temporary/status"
  ledger cover "$state" Staged.sh "$rule"
  ledger finding "$state" Staged.sh "$rule" Provision Finding
  ledger json "$state" > "$temporary/json"
  jq -e '.finalized == false and .files["Staged.sh"].covered and .findings[0].finding == "Finding"' "$temporary/json" >/dev/null
  cover_all
  ledger finalize "$state" > "$temporary/finalize-output"
  [ ! -s "$temporary/finalize-output" ]
  cp "$state" "$temporary/before"
  ledger json "$state" > "$temporary/json"
  cmp "$state" "$temporary/before"
  jq -e '.finalized == true and has("changed_files") and has("dimension") and has("rules")' "$temporary/json" >/dev/null
  ledger status "$state" > "$temporary/status"
  grep -q 'Finalized: true' "$temporary/status"
  grep -q 'Coverage: 4/4' "$temporary/status"
  # Serialization still works on structurally readable but inconsistent state.
  jq '.files["Staged.sh"].covered=false' "$state" > "$temporary/inconsistent"
  ledger json "$temporary/inconsistent" > "$temporary/json"
  jq -e '.finalized == true and .files["Staged.sh"].covered == false' "$temporary/json" >/dev/null
  reject ledger finalize "$temporary/inconsistent" > "$temporary/finalize-output" 2>/dev/null
  [ ! -s "$temporary/finalize-output" ]
  printf '{}' > "$temporary/readable-object"
  ledger json "$temporary/readable-object" > "$temporary/json"
  jq -e '. == {}' "$temporary/json" >/dev/null
}
test_coverage_and_findings() {
  init_design
  reject ledger finding "$state" Staged.sh "$rule" Provision Finding 2>/dev/null
  ledger cover "$state" Staged.sh "$rule"
  ledger finding "$state" Staged.sh "$rule" 'Topic#Provision' 'Finding with "quotes"'
  jq -e '.files["Staged.sh"].covered and .findings[0].provision == "Topic#Provision"' "$state" >/dev/null
  reject ledger finalize "$state" >/dev/null 2>&1
  cover_all
  ledger finalize "$state" > "$temporary/finalize-output"
  [ ! -s "$temporary/finalize-output" ]
  ledger json "$state" > "$temporary/final"
  jq -e '.finalized == true and all(.files[]; .covered) and .findings[0].finding == "Finding with \"quotes\""' "$temporary/final" >/dev/null
  ledger cover "$state" Staged.sh
  jq -e '.finalized == false' "$state" >/dev/null
}
test_rejected_operations() {
  init_design
  reject ledger cover "$state" 'Not changed' "$rule" 2>/dev/null
  reject ledger cover "$state" Staged.sh 'Unknown rule' 2>/dev/null
  reject ledger finding "$state" Staged.sh '' Provision Finding 2>/dev/null
  reject ledger finding "$state" Staged.sh "$rule" 2>/dev/null
  ledger cover "$state" Staged.sh "$rule"
  reject ledger finding "$state" Staged.sh "$rule" '' Finding 2>/dev/null
  reject ledger finding "$state" 'Not changed' "$rule" Provision Finding 2>/dev/null
  jq -e '.findings == []' "$state" >/dev/null
}
test_malformed_and_inconsistent_state() {
  init_design
  cp "$state" "$temporary/original"
  for filter in 'del(.files["Staged.sh"])' '.files["Staged.sh"].covered="yes"' \
    '.finalized=true' '.files["Staged.sh"].rules=["Unknown"]' \
    '.findings=[{file:"Unknown",rule:"Unknown",provision:"p",finding:"f"}]' \
    '.extra=true' '.rules=[]'; do
    jq "$filter" "$temporary/original" > "$state"
    reject ledger finalize "$state" > "$temporary/final" 2>/dev/null
    [ ! -s "$temporary/final" ]
  done
  printf 'not json' > "$state"
  reject ledger finalize "$state" > "$temporary/final" 2>/dev/null
  [ ! -s "$temporary/final" ]
}
test_behavior_ledger() {
  ledger init "$state" "$repo" behavior
  reject ledger cover "$state" Staged.sh "$rule" 2>/dev/null
  ledger json "$state" | jq -j '.changed_files[] | . + "\u0000"' > "$temporary/paths"
  while IFS= read -r -d '' file; do ledger cover "$state" "$file"; done < "$temporary/paths"
  ledger finding "$state" Staged.sh Area Scenario Expected Actual Explanation
  ledger finalize "$state" > "$temporary/finalize-output"
  [ ! -s "$temporary/finalize-output" ]
  ledger json "$state" > "$temporary/final"
  jq -e '.finalized == true and .rules == [] and .findings[0] == {file:"Staged.sh",area:"Area",scenario:"Scenario",expected:"Expected",actual:"Actual",explanation:"Explanation"}' "$temporary/final" >/dev/null
}
test_concurrent_original_worktree_and_authority() {
  invoke '{"barrier":true}'
  [ "$code" -eq 0 ]
  [ "$(cat "$control/design.cwd")" = "$(CDPATH= cd -- "$repo" && pwd -P)" ]
  cmp "$control/design.cwd" "$control/behavior.cwd"
  jq -e -n --slurpfile d "$control/design.initial" --slurpfile b "$control/behavior.initial" \
    '$d[0].changed_files == $b[0].changed_files and ($d[0].rules|length)==2 and $b[0].rules == []' >/dev/null
  grep -q 'Composition.md' "$control/design.prompt"
  reject grep -q 'Composition.md' "$control/behavior.prompt"
  grep -q "$task" "$control/design.prompt"
  grep -q "$task" "$control/behavior.prompt"
  check '.status == "completed" and .design.findings == [] and .behavior.findings == []'
}
test_finalized_results_not_agent_stdout() {
  invoke '{"findings":true}'
  [ "$code" -eq 1 ]
  jq -e -n --slurpfile p "$temporary/result" --slurpfile d "$control/design.result" --slurpfile b "$control/behavior.result" \
    '$p[0].design == $d[0] and $p[0].behavior == $b[0]' >/dev/null
  jq -e -s 'length == 1' "$temporary/result" >/dev/null
  reject grep -q 'This prose' "$temporary/result"
  grep -q diagnostic-design "$temporary/diagnostics"
  grep -q diagnostic-behavior "$temporary/diagnostics"
}
test_unfinalized_or_incomplete_agent() {
  invoke '{"skip_finalize":"design"}'
  [ "$code" -eq 2 ]
  check '.status == "incomplete" and .design.status == "failed" and .behavior.finalized == true'
  invoke '{"forged_output":"behavior"}'
  [ "$code" -eq 2 ]
  check '.behavior.status == "failed" and .design.finalized == true'
  invoke '{"skip_cover":"design"}'
  [ "$code" -eq 2 ]
  check '.design.status == "failed" and .behavior.finalized == true'
}
test_failure_preserves_sibling() {
  invoke '{"fail":"behavior","findings":true}'
  [ "$code" -eq 2 ]
  check '.status == "incomplete" and (.design.findings|length)==1 and .behavior.status == "failed"'
  jq -e -n --slurpfile p "$temporary/result" --slurpfile d "$control/design.result" '$p[0].design == $d[0]' >/dev/null
  invoke '{"fail_after_finalize":"design"}'
  [ "$code" -eq 2 ]
  check '.design.status == "failed" and .behavior.finalized == true'
}
test_standalone_specialized_operations() {
  /bin/bash "$ROOT/Review/Technical Design/Review.sh" "$repo" "$agent" "$task" 'Engineering Rules/*.md' > "$temporary/design"
  /bin/bash "$ROOT/Review/Behavior/Review.sh" "$repo" "$agent" "$task" > "$temporary/behavior"
  cmp "$temporary/design" "$control/design.result"
  cmp "$temporary/behavior" "$control/behavior.result"
  printf '{"skip_finalize":"design"}' > "$control/config"
  reject /bin/bash "$ROOT/Review/Technical Design/Review.sh" "$repo" "$agent" '' "$rule" > "$temporary/design" 2>/dev/null
  [ ! -s "$temporary/design" ]
}
test_finalization_owned_by_agent() {
  # Instrument ledger invocations in a test-only copy of the scripts.
  cp -R "$ROOT/Review" "$temporary/instrumented"
  cp -R "$ROOT/Agents" "$temporary/Agents"
  export REAL_LEDGER_TOOL="$ROOT/Review/Ledger.sh" LEDGER_CALLS="$temporary/calls"
  cat > "$temporary/instrumented/Ledger.sh" <<'WRAPPER'
#!/bin/bash
printf '%s\n' "$1" >> "$LEDGER_CALLS"
exec /bin/bash "$REAL_LEDGER_TOOL" "$@"
WRAPPER
  chmod +x "$temporary/instrumented/Ledger.sh"
  for dimension in 'Technical Design' Behavior; do
    : > "$LEDGER_CALLS"
    if [ "$dimension" = Behavior ]; then
      /bin/bash "$temporary/instrumented/$dimension/Review.sh" "$repo" "$agent" "$task" > "$temporary/child"
    else
      /bin/bash "$temporary/instrumented/$dimension/Review.sh" "$repo" "$agent" "$task" "$rule" > "$temporary/child"
    fi
    jq -e -s 'length == 1 and .[0].finalized == true' "$temporary/child" >/dev/null
    jq -e -Rn '[inputs] | (map(select(. == "finalize")) | length) == 1 and .[-1] == "json"' "$LEDGER_CALLS" >/dev/null
  done
}
test_rule_patterns_and_relative_paths() {
  cp "$agent" "$temporary/Other Backend.sh"
  chmod +x "$temporary/Other Backend.sh"
  invoke '{}' --agent "$temporary/Other Backend.sh" --rules 'Engineering Rules/Composition.md'
  [ "$code" -eq 0 ]
  check '(.design.rules|length)==2'
  set +e
  (CDPATH= cd -- "$temporary" && "$ROOT/Review/Review.sh" --target 'repository with spaces' --agent './Other Backend.sh' \
    --rules 'Engineering Rules/*.md' --task Task.md) > "$temporary/result" 2> "$temporary/diagnostics"
  code=$?
  set -e
  [ "$code" -eq 0 ]
  check '.status == "completed"'
  invoke '{}' --rules 'No matching rules/*.md'
  [ "$code" -eq 2 ]
}
test_configuration_and_help() {
  invoke '{}' --task "$temporary/missing"
  [ "$code" -eq 2 ]
  check '.design.error.kind == "configuration" and .behavior.error.kind == "configuration"'
  [ ! -e "$control/design.ready" ]
  invoke '{}' --behavior-context "$temporary/missing"
  [ "$code" -eq 2 ]
  check '.design.error.kind == "configuration" and .behavior.error.kind == "configuration"'
  reject /bin/bash "$ROOT/Review/Technical Design/Review.sh" "$repo" "$agent" '' 'No matches/*.md' >/dev/null 2>&1
  reject /bin/bash "$ROOT/Review/Behavior/Review.sh" "$repo" "$agent" '' "$rule" >/dev/null 2>&1
  [ ! -e "$control/design.ready" ] && [ ! -e "$control/behavior.ready" ]
  chmod a-r "$task"
  if [ ! -r "$task" ]; then
    invoke '{}' --task "$task"
    [ "$code" -eq 2 ]
    check '.design.error.kind == "configuration"'
    [ ! -e "$control/design.ready" ]
  fi
  chmod u+r "$task"
  "$ROOT/Review/Review.sh" --help > "$temporary/output" 2> "$temporary/help"
  [ ! -s "$temporary/output" ] && [ -s "$temporary/help" ]
}
test_no_changes_and_unusual_paths() {
  git -C "$repo" add .
  git -C "$repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm Stable
  init_design
  ledger finalize "$state" > "$temporary/finalize-output"
  [ ! -s "$temporary/finalize-output" ]
  ledger json "$state" > "$temporary/final"
  jq -e '.files == {} and .findings == []' "$temporary/final" >/dev/null
  printf 'new\n' > "$repo/space and quoted name.sh"
  printf 'new\n' > "$repo/another spaced name.sh"
  init_design
  jq -e '.changed_files == ["another spaced name.sh","space and quoted name.sh"]' "$state" >/dev/null
  cover_all
  ledger finalize "$state" >/dev/null
}
test_parent_validation() {
  invoke '{}'
  [ "$code" -eq 0 ]
  for filter in '.status="incomplete"' 'del(.design.files)' '.behavior.files["Staged.sh"].covered=false' \
    '.design.findings=[{file:"Not changed",rule:"Unknown",provision:"p",finding:"f"}]'; do
    jq "$filter" "$temporary/result" > "$temporary/invalid"
    reject jq -e -s -L "$ROOT/Review" -f "$ROOT/Review/Validate.jq" "$temporary/invalid" >/dev/null 2>&1
  done
}
tests='test_init_and_help test_json_and_status test_coverage_and_findings test_rejected_operations test_malformed_and_inconsistent_state test_behavior_ledger test_concurrent_original_worktree_and_authority test_finalized_results_not_agent_stdout test_unfinalized_or_incomplete_agent test_failure_preserves_sibling test_standalone_specialized_operations test_finalization_owned_by_agent test_rule_patterns_and_relative_paths test_configuration_and_help test_no_changes_and_unusual_paths test_parent_validation'
for test in $tests; do
  (set -e; setup; "$test")
  code=$?
  if [ "$code" -eq 0 ]; then printf 'PASS %s\n' "$test";
  else printf 'FAIL %s (%s)\n' "$test" "$code" >&2; failed=$((failed+1)); fi
done
printf '%s failures\n' "$failed"
[ "$failed" -eq 0 ]