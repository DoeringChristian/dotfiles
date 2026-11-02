# Reviewing a report

Review each changed report according to its question, not a universal section
list. For a research-direction report, use the standard of a good paper in its
field. For dataset inspection, transformation validation, or comparisons, judge
whether the procedure, evidence, limitations, and decision are clear and sound.
The Stop hook requests this review for every changed report.

Apply R1–R9 below to the actual scope. For example, R2 asks whether inspection
checks are reproducible; R6 applies only when baselines/variants are relevant.
Mark an item not applicable with a short reason when necessary; do not invent a
method, baseline, literature review, or architecture figure to satisfy it.

Read the report as its reader sees it: the built page under
`.cairn/build/<slug>/`, not only the Markdown source. Pretend you have
not seen the code or the conversation. Open every figure that the Methods
section relies on and look at it.

Judge the report against how a well-written paper presents the same work, not
against a checklist. Do not add what a good paper would leave out:

- exhaustive hyperparameter lists (the configs hold them);
- a diagram of every module;
- definitions of standard notation;
- restated background.

A missing thing fails an item only when a reader of a good paper would miss it.
Padding, repetition, and generic text fail item R9. Fail an item only for a
problem a reviewer would require the authors to fix, and leave minor points
alone.

## Items

- **R1 problem**: the problem is stated precisely (inputs, outputs, unknowns,
  and the objective), and notation is introduced before it is used.
- **R2 reimplementable**: an expert in the field could reimplement the core
  method from the Methods text, with the configs for settings. The objective or
  forward pass, the update rules or the algorithm, and every stage are there,
  not only named.
- **R3 explained**: each non-standard component or term says what it does and
  why it is there; a reader learns what would change without it. Every named
  method, component, or quantity uses a term from the literature, cited; a
  name made up for this project fails the item.
- **R4 figures**: where a paper in this field would show the model or mechanism
  in a figure, the report has one, it matches the text, and the text says what
  to see in it. Examples: the architecture of a neural network, the
  computational graph of a multi-part model, a toy example of a key
  operation, or how the state evolves in an iterative method. It also fails when a
  figure the user asked for is missing or was replaced by a different one, or
  when a figure only decorates (the tooling, a linear list of steps, a
  restated table).
- **R5 rationale**: the report says why the method should work, which
  assumptions it relies on, and where it may fail.
- **R6 baselines**: every baseline and variant is defined before results use its
  name, and its difference from the proposed method is clear.
- **R7 design**: the data, protocol, fairness controls, and the comparison
  behind each claim are stated. The details the main results depend on are given
  or pointed to; for learned models, these are the data splits, the training
  procedure, and how the settings that matter were chosen.
- **R8 claims**: the abstract and conclusion claim no more than the evidence
  shown supports. Smoke tests and proxies are not presented as evidence, results
  come only from the report's declared inputs (completed artifact versions), and
  no result number is typed into the prose where it should be computed from an
  input (a typed design constant is fine).
- **R9 concise**: there is no padding, filler, or repetition between sections,
  and the length fits the content.

## After the review

Fix every failed item in the report sources and rebuild. Fix the problem, not
the wording that revealed it: never pad a section to make an item pass. Then
finish, and tell the user which items, if any, you left open and why.
