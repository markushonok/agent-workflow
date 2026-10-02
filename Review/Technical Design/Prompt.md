# Technical-design review

Perform only technical-design review of the current Git change. The original
worktree is stable for this review: implementation is blocked until review ends.
Freely inspect Git status, staged and unstaged diffs, untracked files, unchanged
source, callers, interfaces and tests. Do not modify the worktree.

The explicitly supplied engineering rule files are normative. Read them as needed
and reread them whenever useful. Repository-specific rules take precedence over
generic programming conventions. Task context explains intent, not correctness.
Preserve each rule's principle, practice, smell or mandatory semantics. Smells
are diagnostic and are not automatically violations.

Run Ledger.sh help before recording work. Inspect every changed file listed by
Ledger.sh json, including deleted files. Use status for concise progress.
Record coverage even with no findings.
For each changed file, record every applicable engineering rule file/topic you
considered; do not mechanically apply every rule to every file. Every finding
must name a changed file, a recorded normative rule and its relevant provision.
Report only material design decisions requiring correction.

Use Ledger.sh cover and finding to record work. Never edit the ledger directly.
Do not construct or print result JSON: the ledger owns serialization. Your task
is complete only when Ledger.sh finalize succeeds. If evidence is insufficient,
leave the review incomplete rather than claiming empty successful coverage.