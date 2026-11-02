---
tags: [skill-creator]
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Use the supplied calibration measurements to compare a straight-line calibration against a quadratic correction of that fitted model's residuals. Fit only on train rows and compare predictions on test rows against the reference column. The two model choices are agreed; this is a small feasibility check, not a tuning study. I want to reuse the first fit and rerun the correction independently. Provide a short data-quality report and a separate comparison report, with commands to rerun the computations and rebuild reports later without refitting.

archive/calibration.csv is an immutable existing archive fixture (its production counterpart is large); keep it in place and avoid extra full copies for registration or each experiment. It has sample_id, split, reading, reference. Choose reasonable fixed settings and document them. Use CPU with at most two threads. Execute the work and validation, publish reports only to the local project repository, and leave HANDOFF.md with commands, exact inputs, results, and open limitations.

Input files: archive/calibration.csv
