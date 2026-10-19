# Research development and review

## Develop the method

Establish the question, inputs, outputs, objective, state and update rules with
the user. Resolve consequential ambiguities with equations, pseudocode or a
small example, and record decisions in config, implementation and Methods.
Revisit the interpretation when implementation exposes a new ambiguity.

Stay within the framework's abstractions: PyTorch `nn.Module`,
`Dataset`/`DataLoader` and `torch.optim`; Mitsuba plugins, `mi.render`, Dr.Jit
array operations/autodiff and `mi.traverse`; the equivalent native extension
points for other frameworks. Read the corresponding framework skills when
applicable. Document a necessary departure rather than silently building a
parallel framework. Test compatibility against a reference implementation
when correctness depends on matching it.

Make mechanisms inspectable with small examples: intermediate states,
transformations, objectives, update directions, trajectories, baseline
comparisons, ablations and failures. Generate illustrations with project code,
not a second implementation. Use reusable plotting functions and a consistent
visual grammar across methods, seeds and runs: fixed colors, ordering, scales,
limits, normalization and aggregation. Set cross-run limits from shared config,
not independently per run. Do not change the scientific problem to improve a
result; disclose approximations that affect its meaning.

Research related work through primary papers, documentation and source code.
Record close prior art and adjust novelty claims accordingly. Prefer faithful
adaptations of authoritative baselines: inspect their relevant execution path,
version, configuration and evaluation protocol, and disclose deviations.
Agree which comparisons test the proposed advantage. Begin with a bounded
feasibility study; show the evidence and establish feasibility before expensive
sweeps or scaling. Record budget, metrics, tolerances and failure cases.

For effects a metric misses, preserve original outputs and add diagnostics
that isolate the effect. Use an established metric when its assumptions fit;
otherwise validate a new measurement against positive, negative and
confounding examples. Keep uncertain perceptual interpretations explicit.

## Write as a paper

The full requirements are in [writing-methods.md](writing-methods.md), with
a [worked Methods example](example-methods.md). Read those before writing
Abstract, Background or Methods; this summary does not replace them.

A direction report is a coherent current account, not an activity log. Use:
Abstract; Introduction; Background and related work; Methods; results and
discussion around the research question; Conclusion. Add focused subsections
or appendices as needed. The abstract states question, approach, principal
supported result, qualification and current decision.

Methods should let an expert reimplement the method with configs for detailed
settings. Define the problem and notation, objective/forward pass, update
rules or algorithm, nonstandard components and their purpose, rationale,
assumptions and failure modes. Describe implementation choices that affect
results and the experimental design. Keep terminology established in the
field; describe new constructs plainly rather than inventing names.

Explain each baseline/variant before results use it. A compact method table
can identify what each method predicts/stores, what changes, and what is held
constant. State the fairness boundary: data/splits, seeds, compute/parameter
budget, initialization, training schedule, stopping rule and evaluation.
Mark confounded comparisons. Tie each claim to its actual comparison.

Add figures where they explain the model or mechanism: a network architecture,
a computational graph for interacting components, or a toy operation computed
with project code. Label them with the same notation as Methods and explain
what to see. Avoid decorative tooling diagrams or diagrams of a linear list
of steps. Use findings for decision-relevant conclusions and metric cards for
values that affect the decision; avoid repeating evidence across sections.

## Review before handoff

Use the full [R0–R9 rubric](review.md), including the paper-structure check.
The Stop hook requests this review after changed reports have been rebuilt.

Read the built report as a field expert unfamiliar with the conversation and
inspect its figures. Fix material failures in the sources and rebuild:

- Is the problem precise and notation introduced before use?
- Could an expert reimplement the method, including its updates/stages?
- Are nonstandard components explained and established terminology cited?
- Do mechanism figures match code and text and serve a scientific purpose?
- Are rationale, assumptions and failure modes explicit?
- Are baselines defined and differences clear?
- Are protocol, fairness controls and comparisons behind claims stated?
- Do claims match finished-run evidence from declared inputs, with smoke tests
  and proxies identified and all experimental numbers derived from files?
- Is the account concise, current and free of padding or repeated results?

Report unresolved scientific or review issues candidly. Never pad text merely
to satisfy a checklist.
