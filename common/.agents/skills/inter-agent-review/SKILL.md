---
name: inter-agent-review
description: >-
  Independent cross-review between Codex and Claude. Use before handing off
  substantive work: Codex asks Claude to critique it, and Claude asks Codex.
  Also use when explicitly asked for an independent or other-agent review.
  Reviewer sessions never delegate again.
---

# Inter-agent review

The working agent owns the task and edits. The other agent independently checks
the result and challenges its reasoning. A second agent of the same family does
not satisfy this review.

## When and how

- Before handing off substantive code, configuration, analysis, or writing, get
  one review from the other agent. Routine acknowledgments and status updates do
  not need a review. The user can waive it for a task.
- For a costly or consequential design, review the concrete plan before building
  it as well. Do not delay independent implementation work while waiting.
- First finish the work and run appropriate checks. Give the reviewer the user's
  request, constraints, scope, relevant files, exact diff or base commit, and test
  commands/results. Include untracked files and submodule changes when relevant.
  Separate evidence from your interpretation; do not supply the desired verdict.
- Ask for specific defects, missed requirements, unnecessary complexity, weak
  assumptions, regressions, and inadequate tests. Findings need evidence, a
  concrete consequence, and a suggested correction. Distinguish blockers from
  optional improvements. A clean review is valid; do not manufacture criticism.
- Keep edits stable during a review. If you change the reviewed work, give the
  reviewer the new diff and findings being addressed. A verdict covers only the
  version actually inspected.

## Invoke the other agent

Use a genuine cross-provider agent tool if available, with the restrictions below.
Otherwise use the installed CLI through the bundled runner. Write a review brief
to a private temporary directory; include the diff there when the reviewer cannot
run Git. Claude's reviewer has file-reading tools only. Codex runs in a read-only
sandbox with web search disabled and must limit its tools to local inspection.
The sandbox does not constrain configured MCP/connectors: the reviewer must not
use them. Claude's invocation disables user hooks and MCP servers; managed policy
hooks remain subject to the host's policy.

```bash
review_dir=$(mktemp -d)
# Write request, scope, evidence, and the diff to "$review_dir/brief.txt".
python3 ~/.agents/skills/inter-agent-review/scripts/review.py \
  --author codex --cwd "$PWD" \
  --brief "$review_dir/brief.txt" --output "$review_dir/review.txt"
```

Use `--author claude` when Claude is doing the work. The runner chooses the other
CLI; it does not override its model. Read the review file only after a successful
exit. Launch this command using the host's background execution facility and
continue sending normal progress updates. Set any host execution timeout longer
than the runner's timeout. Default timeout: ten minutes;
`--timeout` changes it. Catchable interruptions terminate the reviewer process
group too; a forced SIGKILL cannot be handled by the runner. Never bypass
permissions to make a review run.

The reviewer is advisory and read-only: no edits, commits, pushes, installs,
external messages, expensive jobs, or further agents. The working agent runs any
additional tests suggested by the reviewer. A review does not authorize new work
outside the user's request.

## Resolve the review

Assess each finding yourself. Verify claims against the code, data, or sources;
fix valid problems and run relevant checks. Reject mistaken findings with reasons.
Do not implement changes merely to secure agreement. For material fixes, get a
focused follow-up review; normally stop after two review rounds. If disagreement
remains, explain the evidence and unresolved issue to the user.

In the handoff, briefly state who reviewed, what was fixed, and any substantive
unresolved findings. A reviewer verdict is not a substitute for tests. If the
other CLI/tool is missing, unauthenticated, times out, or is unavailable, continue
permitted checks and disclose that independent review did not complete. Never
claim a review happened or silently substitute the same model family.

## Prevent recursion

If `INTER_AGENT_REVIEW=1` or the task says `REVIEWER_ONLY`, you are the reviewer:
inspect and return findings directly. Do not invoke this skill's runner or start
any agent. The runner sets both markers and rejects nested invocations.
