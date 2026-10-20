# Writing a direction report

Read this before writing or revising a direction report's Abstract,
Background, or Methods, and read the worked example
[example-methods.md](example-methods.md) once per project. Report syntax
(figures, values, diagrams, callouts) is in [reports.md](reports.md).

The standard is a well-written paper in the project's field: a reader who knows
the field, but not this project or its code, understands what the method does,
why it should work, and how to reimplement it. Write to that standard, not to a
length: a paper says what the reader needs once, in the order they need it, and
leaves the rest to the code and configs. Before you finish, you review every
changed direction report against [review.md](review.md) (see "The review"
below), so know its items before you write.

## The spine

Author every direction report with this ordered spine (how reports are
organized is in [reports.md](reports.md)):

1. `## Abstract`: question, approach, principal result, important
   qualification, and current decision, self-contained.
2. `## Introduction`: how this direction serves the project's shared target
   (stated briefly, or linked to the published report's explicit `#introduction` anchor when another
   report defines it), its research question,
   scope, and why the comparison matters.
3. `## Background and related work`: prior and related work, the baselines,
   and the comparison ladder, for a technically literate reader who has not
   seen the code.
4. `## Methods`: the method, then the experimental design.
5. Results and discussion sections arranged around the research question, not
   the chronology of runs: findings, quantitative evidence, diagnostics,
   ablations, contradictions, limitations.
6. `## Conclusion`: the answer the evidence supports, its limits, and the next
   decision or experiment.

Add Results, Discussion, Limitations, or Appendix sections when they help; keep
the Abstract first and the Conclusion last. Put hidden loading code in a
preamble and visible metrics inside a named section.

## Methods

Methods is where the user checks that the implementation matches the idea. Write
it before results are discussed, and revise it whenever the method changes, so
it never describes an earlier version. A good Methods section usually covers, in
the order that suits the method:

- **the problem**: inputs, outputs, unknowns, and the objective, with notation
  introduced before it is used and kept the same in equations, figures, and the
  text;
- **the method itself**, stated, not only named: its objective or forward pass
  and its update rule or training procedure as equations, with an algorithm
  (numbered steps) when it is iterative or has stages. Each non-standard term
  gets a sentence on what it does and why it is there. Standard notation and
  textbook components need no explanation;
- **why it should work**: the intuition, the assumptions it relies on, and
  where it may fail, each assumption tied to the experiment that tests it;
- **its relation to the baselines** in the same notation, so each difference
  is one term, step, or setting;
- **the implementation choices that affect results**: discretization,
  initialization, how the settings that matter were chosen, numerical
  safeguards, cost;
- **the experimental design**: data and splits, protocol, the fairness
  boundary, and which comparison supports each claim.

Use subsections where the method is large enough to need them, named for their
content. State each setting the results depend on, and point to the run's
configs (`configs/experiment/<name>.yaml`, captured with the resolved config in the run's provenance artifact)
for the rest instead of listing every value. One definition per method: if the
method changed, rewrite the section rather than describing both versions.

### Figures that explain the method and the setup

A figure explains a mechanism or a setup, not a result. Add one wherever a good
paper in this field would have one (most method papers have at least an
overview figure and a setup figure), and refer to it where its concept is
introduced, saying what to see in it:

- **An overview of the method**: the problem and the idea in one picture,
  usually real inputs, the key intermediate quantity, and the output, connected
  by the method's operators and labelled with its symbols. This is the figure a
  reader looks at first; it is not a flow chart of boxes.

- **A neural network's architecture** as a designed schematic (see Figures and
  diagrams in [reports.md](reports.md)), at the depth a paper figure would
  show: each block is a component the text names, checked against the model's
  code. Mark what this direction adds or changes.
- **The model as a graph** when it has several interacting parts: its inputs,
  parameters, latent variables, intermediate quantities, and outputs, and how
  each depends on the others, labelled with the symbols of the equations. A
  single equation needs no graph.
- **A toy example of a key operation**: before and after on a small input, a
  one-dimensional slice, a small grid, the geometry of a constraint. Compute it
  with the project's own code (a `{python}` block importing captured project
  functions, or an illustration experiment whose figure is logged as an artifact), never with
  a separate reimplementation or a hand-drawn approximation, so the figure
  shows what the code does.
- **The experiment setup**: what the experiment physically or geometrically
  consists of, as a paper's "experimental setup" figure shows it. For example
  the scene with its camera, lights, and object poses; the sensor and emitter
  layout; the sampling domain and where training and test points lie; the
  test inputs as a grid of thumbnails; the perturbation or degradation applied;
  what is held fixed and what is varied, with the varied parameter's range.
  Draw geometry from the run's resolved config to scale (positions, angles,
  extents, coordinate axes), and render or plot the real test data, so the
  figure shows the setup the results came from. Do not hand-draw it from
  memory.

Do not draw the report or run tooling, a linear chain of protocol steps (write
it as a numbered list; show the setup the steps act on instead), or a
restatement of a table or of the text above it.

## Terminology

Use the field's established terms, and only those. Give a method, component,
quantity, or effect a name only when an existing paper uses that name for the
same thing, and cite that paper where the term first appears. Do not invent
words, names, acronyms, or labels for your own constructs, and do not turn a
config key or code identifier into a term in the prose. Describe a new thing
plainly instead ("the residual over pairs that cross a boundary", not "the
boundary leak score") and use the same description every time. If the
description is too long to repeat, define a symbol for it in Methods.

## Background and related work

**Related work is researched, not recalled.** Before the method is settled, and
again when the question changes, populate Background and related work through a
literature and prior-art search. Run it as a research subagent when the harness
provides one, and give it the research question, the proposed mechanism, and
the baselines, but not the desired answer. It searches papers, preprints,
documentation, and open-source code for the same or similar ideas and returns
sources with links and a one-line relation to this project. Cite the relevant
sources, and cross-reference the project's other direction reports on related
ideas. Flag prior art where the reader needs it:

```markdown
::: {.callout}
**Close prior work: <short name>**

<Source, with link> already does <what>. This report differs only in
<difference>, so it is a replication or an extension, not a new idea.
:::
```

Use an explicit prior-art callout whenever the idea, or a close variant, already exists. Name what
remains new, if anything, and let it change the plan (replicate first, reuse
the reference implementation, or narrow the claim). Never omit a discovered
overlap because it weakens the novelty of the work.

**Define every method before results use its name.** Background and related
work holds a compact table whose first column is `Method`, with columns such as
`What it does`, `Difference from baseline`, and `Held constant`. Keep it to
decision-relevant methods; move a long variant catalog to its own direction
report. A label such as "no sharing", "official", "tuned", or "ours" is not an
explanation: state what each method stores or predicts, which parameters are
shared, independent, quantized, frozen, or learned, which training or inference
operations change, and what mechanism the change tests. An ablation names the
single removed or substituted component. A ladder of baselines distinguishes
the authoritative baseline, faithful reimplementation, matched-strength
control, proposed method, and ablations.

**State the fairness boundary**: data and split, seeds, budget, parameter count
or rate, initialization, optimizer and schedule, stopping rule, and evaluation.
Mark comparisons that change several factors as confounded.

## Summaries and findings

Metric cards hold only values the next decision depends on; each label and
detail says what is compared, whether higher or lower is better, the evaluated
population, and the aggregation. Findings hold only decision-relevant claims;
supporting numbers go to the evidence sections. Say each result once, where it
is discussed, and link to it elsewhere instead of repeating it.

## The review

When you finish a turn in which a direction report's sources changed, the
skill's Stop hook (`scripts/report_gate.py`) checks that the report was rebuilt
and then sends you back once to review it against [review.md](review.md). Read
the built report as its reader would, decide each item, fix what fails in the
sources, and rebuild. Fix the problem, not the wording that revealed it: never
pad a section to make an item pass, and tell the user which items you left
open and why.

On a host that does not execute Stop hooks, run the gate explicitly with the
project root as its `cwd`, carry out the same whole-report review, then run it
with `stop_hook_active: true` only after that review. A successful build does
not substitute for deciding R1–R9.
