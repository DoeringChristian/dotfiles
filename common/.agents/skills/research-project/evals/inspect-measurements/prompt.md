---
tags: [skill-creator]
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Inspect archive/sessions.csv and give me a concise report on whether these measurements are ready for analysis: missing readings, duplicate sample IDs, and shifts between batches. Show the evidence and limitations without changing or cleaning the source. I do not need a predictive model. Make the report reproducible so I can rebuild it later.

The file is a small fixture of an existing large immutable archive; keep its bytes in place rather than copying it into a new data store. Columns are sample_id, batch, reading. You can make reasonable decisions without follow-up questions. Use CPU with at most two threads. Execute and validate the work, publish only to the local project repository, and leave HANDOFF.md with commands and any remaining issues.

Input files: archive/sessions.csv
