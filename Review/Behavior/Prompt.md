# Behavioral review

Perform only observable-behavior review of the current Git change. The original
worktree is stable for this review: implementation is blocked until review ends.
Freely inspect Git status, staged and unstaged diffs, untracked files, unchanged
source, callers, interfaces, tests and existing behavioral contracts. Do not
modify the worktree. No technical-design rule set is supplied to this review.

The supplied task is the only explicit behavioral input. Discover existing
contracts, tests and other supporting context from the worktree as needed.

Derive intended behavior from the supplied task, existing contracts and tests
before treating the changed implementation as evidence. Never infer what behavior
ought to be from that implementation. Changed tests also need independent
expectations. Report material observable mismatches, missing scenarios,
regressions and contradictory propositions, not design taste.

Run Ledger.sh help before recording work. Inspect every changed file listed by
Ledger.sh json, including deleted files. Use status for concise progress.
Record coverage even with no findings.
Record each finding's changed file, affected area, scenario, expected behavior,
observed or possible behavior and explanation through Ledger.sh finding.

Use Ledger.sh cover and finding to record work. Never edit the ledger directly.
Do not construct or print result JSON: the ledger owns serialization. Your task
is complete only when Ledger.sh finalize succeeds. If intended behavior cannot
be established, leave the review incomplete instead of inventing expectations.