# Worktree review and ledger

The review subsystem is shell orchestration around two independent agents:

```text
worktree = review context
Git change = review scope
Prompt = reviewer role and procedure
Rules/task = review authority
Ledger = coverage and findings
finalize = completion validation and finalized marker
json = current complete ledger state serialization
```

Technical Design and Behavior run concurrently in the original worktree. The
caller must block implementation and keep that worktree stable until both finish.
Reviewers may read unchanged source, callers, interfaces, tests and contracts and
inspect Git freely. They must not modify the worktree. Only review ledgers and
prompts are temporary; repository context is not materialized or restricted.

## Platforms and dependencies

Requires Bash (compatible with macOS Bash 3.2), Git, jq and ordinary shell tools.
Supported environments are macOS, Linux and Windows through Git Bash, not native
cmd.exe or PowerShell. No Python, Perl, schema tooling or shell test framework is
required.

## Invocation

```sh
"Review/Review.sh" \
  --target "/path/to/repository" \
  --agent "/path/to/Compatible Runner.sh" \
  --rules "Engineering Rules/*.md" \
  --rules "Other Rules/Naming.md" \
  --task "/path/to/Task.md" > report.json
```

- `--target`: original Git worktree with an existing HEAD commit.
- `--agent`: executable implementing the runner contract below.
- `--rules`: required engineering rule file or shell glob, repeatable. Quote
  patterns so the caller's shell does not expand them. Relative patterns resolve
  from the target worktree. Each pattern must match readable files. Matches are
  sorted and deduplicated deterministically; no recursive discovery is performed.
- `--task FILE`: optional task authority, the only explicit behavioral input,
  supplied to both reviewers.

Other relative paths resolve from the caller's working directory. Quote paths
with spaces. Rule and task filenames must not contain newlines; changed source
filenames use NUL-delimited Git output and may contain spaces or newlines.
Explicit input files must exist and be readable. Specialized operations validate
their own inputs before invoking an agent. An unmatched or unreadable rule pattern
fails Technical Design; the parent still collects Behavior's result.

Exit codes for `Review/Review.sh`:

- **0**: both reviews completed with no findings.
- **1**: both reviews completed with findings.
- **2**: incomplete or failed review, including configuration failure.

Stdout is one validated JSON document; diagnostics use stderr. A successful sibling
is preserved when the other reviewer fails. Findings are never infrastructure
failures and never summarized, deduplicated, ranked or reinterpreted by the parent.

## Roles and authority

`Review/Technical Design/Review.sh` resolves the supplied rule patterns. Its agent
must read and reread those ordinary Markdown files as needed. They are normative;
repository-specific rules take precedence over generic programming conventions.
Principles, practices, smells and mandatory requirements retain their documented
meaning. Smells alone are not automatic violations. The ledger records applicable
rule files/topics per changed file, not a checklist of every rule for every file.

`Review/Behavior/Review.sh` receives the task, current Git change and repository
context, but no Technical Design rule set. Its agent derives intended behavior
from the task, existing contracts and tests discovered in the worktree, rather
than from the changed implementation. Both agents can inspect the repository.
Their responsibilities and explicitly supplied authorities remain distinct; there
is no source sandbox.

Specialized operations can also run directly:

```sh
"Review/Technical Design/Review.sh" "$repo" "$agent" "$task" "Engineering Rules/*.md"
"Review/Behavior/Review.sh" "$repo" "$agent" "$task"
```

Pass `""` for absent task context. Each operation initializes its own ledger,
prepares its role prompt, runs one agent, then reads `Ledger.sh json` and verifies
the returned state is finalized and valid. Only the agent calls `finalize`; the
specialized script never finalizes on its behalf. Exit 0 means the operation
completed, even with findings; exit 2 means failure with stderr only. The parent
owns the completed-with-findings exit code.

## Replaceable agent runner

```text
runner --workspace DIRECTORY --prompt FILE
```

`Agents/Run.sh EXECUTABLE DIRECTORY PROMPT` changes to DIRECTORY and executes the
runner. DIRECTORY is now the original worktree; the established flag name is
retained. The generic boundary has no review, ledger, Git, model or provider
semantics. Execution must exit zero on completion and nonzero on failure.

Specialized operations provide `REVIEW_LEDGER_TOOL` (absolute Ledger.sh path) and
`REVIEW_LEDGER` (this review's state path). Their prompts name the same paths.
Agents use the tool to record their work; they do not generate result JSON. Agent
stdout is opaque and discarded; runner diagnostics pass through stderr.
Harness-specific settings, including disabling automatic project-instruction
discovery when supported, belong in the concrete adapter. Timeout policy also
belongs to that adapter or an outer orchestration layer.

## Ledger contract

Run `Review/Ledger.sh help` for the complete argument syntax. Main operations:

```text
init       discover Git scope and initialize every changed file as uncovered
status     human-readable review progress
json       current complete ledger state as JSON, before or after finalization
cover      record file coverage and, for design, applicable normative rule paths
finding    append a domain-specific finding
finalize   validate completeness and consistency and mark finalized; no stdout
```

Git scope is the union of staged changes relative to HEAD, unstaged changes and
non-ignored untracked files. Deleted paths are included. Rename detection is
disabled for scope enumeration so both old and new filenames are accounted for.
An unchanged file is available as context but cannot be a ledger finding's changed
file. An empty change can finalize with empty coverage and findings.

Each changed file must be covered even when it has no findings. Technical Design
coverage records only applicable rule paths, allowing an empty applicable set.
Design findings contain `file`, `rule`, `provision` and `finding`; the normative
rule must already be recorded for that changed file. Behavior findings contain
`file`, `area`, `scenario`, `expected`, `actual` and `explanation`; Behavior
coverage has no engineering-rule semantics.

Ledger mutations validate state with jq and replace it only after a valid update.
Mutations reset `finalized`. Every changed file must be covered before
finalization succeeds. A reviewer that exits without successfully finalizing
cannot produce a completed result, even if it prints plausible JSON. Never edit
ledger JSON directly. One reviewer owns one ledger and invokes its commands
sequentially; the subsystem does not implement concurrent writers or locking.

`json` is read-only: it parses one ledger object and emits every field without
checking coverage, finding consistency or completion. It is valid before
finalization and useful for inspecting incomplete state. `status` is a concise
progress view; `finalize` validates completion and updates the marker silently.
After the agent exits, the specialized script reads `json`, validates the finalized
state, and returns that same JSON. An unfinalized ledger remains a failed review.

Completed child JSON is the complete ledger state: `dimension`, `finalized`,
`changed_files`, `rules`, `files` and `findings`. Design includes authoritative rule
paths, never rule contents; Behavior's `rules` array is empty. The parent returns:

```json
{
  "status": "incomplete",
  "design": {
    "status": "failed",
    "error": {"kind": "review_failed", "message": "design review did not finalize successfully"}
  },
  "behavior": {
    "dimension": "behavior", "finalized": true,
    "changed_files": [], "rules": [], "files": {}, "findings": []
  }
}
```

The public `Schema.json` files document each result type. Colocated `Validate.jq`
files enforce domain fields, coverage, changed-file references and rule references.
`Ledger.jq` validates internal ledger consistency; the parent validates children
and its final aggregate before emission. Runtime validation uses explicit jq
predicates, not a JSON Schema interpreter or a custom JSON parser.

## Local composition and verification

A project's `Workflow/Review.sh` may supply its worktree, rule patterns, task and
default runner. Generic code assumes no project directory names and implements no
rules service.

```sh
/bin/bash Tests/Review.sh
for script in TrimEof.sh Agents/*.sh Review/*.sh Review/*/*.sh Tests/*.sh; do
  /bin/bash -n "$script" || exit
done
```

Tests use deterministic fake agents and real temporary Git repositories. They
exercise ledger scope, coverage, findings, consistency, finalization gates,
worktree execution, concurrent reviewers, authority separation, mechanical
aggregation, stdout purity, exit codes and quoted paths.