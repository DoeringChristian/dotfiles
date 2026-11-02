# Research-project behavior tests

Two isolated mock projects exercise a staged computation with two reports and a dataset-only inspection. Prompts intentionally leave architecture and API choices to the worker. `files/` contains small deterministic fixtures representing persistent immutable archives; `place-files.sh` installs them. Graders are evaluator-only and must not be shown to workers.

Use skill-tester to run each case with fresh Codex and Claude contexts, complete immutable skill snapshots, a hidden rubric, and local storage only. Compare against the previous skill revision when evaluating changes. Read code, recorded Cairn inputs/outputs, reports, and execution logs; a claimed result or unfinished script is not a passing end-to-end result. Check that report rebuilding does not create new computation runs. Separate infrastructure interruptions from observed incorrect behavior.

The initial comparison used Codex's configured default model and explicit Claude Opus 5.5 (`claude-opus-5-5`), with four revised-skill and four old-skill runs. All reached the time limit; outputs are partial, not successful end-to-end projects. Claude transcripts include stream interruptions and API retry events. The retained evaluation includes prompts, frozen snapshots, transcripts, per-assertion grades, and a static review viewer at `/tmp/research-project-eval-t_r0y9qc/review.html`. These temporary files are not a permanent dependency of the cases.

Not exercised: GPU or cluster execution, remote link fallback, actual large-data throughput, directory-manifest scaling, or recovery from interrupted training. The cases are not repeated statistical samples and do not rank the two models.
