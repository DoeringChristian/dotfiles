---
name: skill-tester
description: Forward-test an agent skill with realistic mock tasks in an isolated temporary workspace. Use when reviewing whether a skill changes agent behavior as intended, checking its requirements against produced artifacts, regression-testing a skill revision, or comparing skill-guided behavior without priming the test agent with the expected solution.
---

# Skill Tester

Test skills through observable agent behavior, not by asking an agent to summarize
the instructions or by matching phrases from `SKILL.md`.

## Evaluation boundary

Keep the evaluator and test worker separate:

- The **evaluator** reads the target skill, derives the hidden rubric, designs the
  mock problem, inspects the transcript and artifacts, and assigns verdicts.
- The **worker** receives a fresh context containing only the target skill, the
  mock user request, its isolated workspace, and resources genuinely required to
  perform that request.

Never send the worker the rubric, expected implementation, suspected failure,
prior review, proposed fix, user discussion that produced the skill, or a list of
skill requirements disguised as a task. Do not tell it what behavior is being
measured. Additional context is allowed only when a real user would have to
provide it for the mock task to be solvable.

## Isolate the test in `/tmp`

Create a unique directory such as:

```text
/tmp/skill-test-<skill-name>-<random>/
├── control/       # evaluator-only rubric, notes, and captured evidence
├── skill/         # read-only copy of the target skill
└── workspace/     # the worker's mock project and permitted outputs
```

Copy the complete target skill, including referenced scripts, assets, and
references, into `skill/`. Do not test against partially copied instructions.
Keep the original skill and repository unchanged during the worker run. Do not
copy credentials, unrelated repository files, parent-session transcripts, or
ambient project state into the fixture.

Use a fresh worker context rather than a fork containing the evaluator's
reasoning. Restrict its working directory and side effects to `workspace/`.
Network access, external services, expensive computation, and destructive
operations require the same authorization they would require outside the test;
prefer local fixtures when they preserve the behavior under evaluation.

## Derive a hidden rubric

Before launching the worker, turn the target skill into a compact set of
observable claims. Include:

- the decisions or boundaries the skill is meant to change;
- required artifacts and their important properties;
- safety, reproducibility, disclosure, and validation invariants;
- important prohibited behavior;
- conditional requirements only when the mock task activates their condition.

For each claim, record what evidence would establish it. Do not treat headings,
exact wording, or the presence of copied boilerplate as success. Distinguish:

- **must satisfy** — central to the skill or necessary for correctness;
- **should satisfy** — meaningful quality guidance;
- **not exercised** — outside this mock problem rather than failed.

Do not expand the rubric with preferences absent from the target skill.

## Design the mock problem

Choose the smallest realistic request that exercises the skill's central
behavior end to end. It should leave normal implementation choices open while
making the intended outcome inspectable. Seed only the files and data a real
user would plausibly provide.

Avoid prompts that enumerate the rubric. For example, ask for a small research
study rather than instructing the worker to create every file named by a
research-project skill. A passing result should require the worker to apply the
skill, not mirror the mock prompt.

Use additional focused cases only when one task cannot exercise a critical
branch, such as a failure path, optional mode, unsafe input, or ambiguous user
request. Keep cases independent. Do not grow one oversized fixture merely to
cover every sentence in the skill.

## Run the worker

The worker prompt should normally contain only:

```text
Use the skill at <temporary-skill-path> to complete this request in
<temporary-workspace>:

<realistic mock user request>
```

Add fixture-specific facts only when required to solve the task. Require the
worker to perform the work and validation, not to explain what it would do. Save
its transcript or final response in `control/` when the execution mechanism
supports that without exposing `control/` to the worker.

If the worker cannot start because of missing infrastructure, unavailable
credentials, or unsupported tooling, classify the case as blocked. Do not
silently replace the worker with the evaluator or feed it hints from the rubric.

## Judge evidence

Inspect the actual workspace, commands, validation output, and worker handoff.
For every rubric claim, assign one verdict:

- **pass** — direct evidence establishes the claim;
- **partial** — some evidence exists but a material part is missing;
- **fail** — behavior or artifacts contradict the claim;
- **not exercised** — the mock did not activate the requirement;
- **blocked** — infrastructure prevented a meaningful test.

A worker assertion is not evidence by itself. Prefer file contents, diffs,
command output, rendered artifacts, and reproducible checks. Evaluate scientific
or domain claims only to the degree the fixture can support them; do not turn a
smoke test into evidence of correctness.

When diagnosing a failure, determine whether it comes from the skill, the mock
problem, the worker, or the harness. Re-run only when that distinction cannot be
made from existing evidence. Do not coach a failed worker into passing the same
case; revise the skill or fixture first, then start a new clean run.

## Optional control comparison

When the skill's effect is uncertain and the added cost is justified, run the
same mock request with an equivalent fresh worker that does not receive the
skill. Keep model, tools, fixture, budget, and prompt otherwise equal. Use the
comparison to identify behavior caused by the skill, not as a requirement that
the unguided worker fail.

## Report concisely

Return:

1. the target skill revision or hash;
2. the mock task and worker context actually supplied;
3. a requirement table with verdict and evidence path or command;
4. the most important failures and residual risks;
5. the overall verdict: **pass**, **pass with gaps**, **fail**, or **blocked**;
6. the retained `/tmp` path when the user may want to inspect artifacts.

Keep detailed transcripts and bulky outputs in `control/`; do not paste them
into the handoff. State explicitly which requirements were not exercised.
Never claim the entire skill is validated from one happy-path mock.

Preserve the temporary fixture through the review handoff. Remove it afterward
only when it is no longer needed or when the user requests cleanup.
