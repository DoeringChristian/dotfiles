# Folio reports

## Use the installed implementation

Folio is the standalone report engine in `~/workspace/folio-reports`. Check
`folio --help`, `folio build --help`, `src/folio/config.py`, and the current
examples when a feature is unclear. At skill creation, its README still shows
some earlier command/config forms; the actual CLI uses `folio build .`,
`folio serve .` and `folio standalone . -o report.html` (no `-C`). Its config is:

```toml
# folio.toml
[project]
render = ["reports/*/report.md"]
output-dir = "_site"
```

This limits discovery to direction reports rather than building every README
in the repository. The builder owns and replaces the output directory; never
place source material or experiment data there.

Keep one single-page report per direction under `reports/<slug>/report.md`,
with local `assets/` for non-result illustrations if needed. Folio generates
an index; an extra overview report is optional only when it adds scientific
content. Preserve the existing renderer rather than reauthoring reports for a
sharing destination.

### Keep each report editorially coherent

A report is the primary communication surface between the user and agent, not
an append-only activity log. Optimize it for a reader who needs to understand
the current method, evidence, and decisions quickly. Keep the narrative
concise, use progressive disclosure for supporting detail, and remove
repetition, stale explanations, superseded conclusions, and figures that no
longer answer an active question. Provenance and decision history live in the
manifest, the MLflow run artifacts, and findings, not in the visible narrative.

When the user requests an edit, clarification, comparison, or more evidence,
first decide what it means for the report's structure. Integrate a local
clarification where its concept is introduced; revise rather than append a
near-duplicate. If the request changes the method, interpretation, or research
question fundamentally, reconsider the section order, framing, summaries,
figures, and whether it belongs in a new direction report. After substantive
updates, read the report as a whole: the abstract must match the evidence,
terminology must be consistent, and the most important open questions must stay
prominent.

### Use callouts for synchronization

Use a callout when the reader could otherwise miss something that changes the
shared understanding or the next decision: an unresolved assumption, a
surprising limitation, contradictory evidence, overlapping prior art, a risk of
misinterpretation, a decision gate, or a question for the user. Keep each one
short, give it a specific title, and say what response is needed. Remove or
rewrite it once resolved. Types: `question` (input needed from the user),
`decision` (pending or confirmed choice), `prior-art` (the idea or a close
variant already exists), `warning` or `risk` (consequential limitation), and
`important` (context the reader must not overlook).

```markdown
!!! question "Which reference behavior is authoritative?"
    The two candidate baselines use different boundary handling. Confirm the
    intended behavior before feasibility results are interpreted.
```

## Declare evidence

````markdown
---
title: Feasibility of the proposed method
inputs:
  evaluation: runs:/EXACT_FINISHED_RUN_ID/evaluation
---

## Abstract

<!-- State question, approach, supported answer and qualification. -->

## Introduction

## Background and related work

## Methods

## Results and discussion

```python exec hide
scores = read_json(inputs.evaluation / "summary.json")
```

Test RMSE: {{ scores['rmse'] }}.

![Per-case errors](input:evaluation/figures/errors.png)

## Conclusion
````

The outer example above is illustrative Markdown; replace the run ID and prose
with actual evidence. All experimental numbers, including summaries and
conclusions, come from input files through `{{ }}` expressions or executable
blocks. Design constants may be stated directly. Keep loading code before any
values that need it; follow the current Folio examples for frontmatter values.

Input URIs must resolve to **directories**. Folio's MLflow adapter downloads
artifacts using MLflow's configured tracking URI/credentials; it does not
query metrics or parameters, check run completion, implement `latest`, or
resolve `models:/` URIs. Before adding a run to a report, query
`MlflowClient().get_run(run_id)` and require `info.status == "FINISHED"` for
scientific evidence. Also verify the expected files and input identity. A
failed-run diagnostic may be discussed explicitly as a failure, never as a
successful trial.

Use exact run IDs and stable artifact paths. Do not overwrite cited artifacts:
MLflow allows later writes, so a run ID is not an immutable content version.
Folio records a directory content hash and read-file provenance in its build
manifest. Preserve that manifest with exported reports; keep files stable
while building and investigate unexpected hash changes rather than silently
accepting a changed result.

Folio's `read_scalars` reads a `metrics.jsonl` file; it does not read MLflow
tracking data. Prefer `read_json` for `summary.json` and CSV/JSON tables for
curves and comparisons. A report may derive plots/statistics from declared
inputs but must not train models, rerun experiments, fetch live metrics, or
invent missing evidence while rendering.

## Author, build, inspect, share

Read [writing-methods.md](writing-methods.md) for the required paper-like
structure and detailed writing guidance, [example-methods.md](example-methods.md)
once per project, and [review.md](review.md) before finishing. Folio retains executable
Python, Matplotlib capture, Plotly JSON figures, Graphviz, formulas, metric
cards, findings, callouts and source locations. Consult the current examples
and renderer for detailed syntax rather than assuming all Cairn features or
cross-report URL forms still match. The input guard catches accidental
undeclared reads; report Python is trusted code, not sandboxed code.

After changing reports:

1. Verify cited runs are finished and all evidence is declared.
2. Run `pixi run report-build`; inspect the rendered page and every added or
   changed figure. Check units, scales, grouping, labels and correspondence to
   the actual evidence.
3. Re-read the whole report: abstract, Methods, findings, discussion and
   conclusion must describe the current implementation and supported claims.
   Fix review failures and rebuild.
4. Use `pixi run report-serve` for local browsing. For a shareable offline file,
   use `folio standalone reports/<slug>/report.md -o <slug>.html`, or
   `pixi run report-share` for the configured collection. Inspect the export
   and deliver it unchanged. Export is not remote publication; upload only to
   a destination within the user's requested scope.

Pasted source-location markers point to the named source line or figure; fix
that source and rebuild. The Folio-adapted Stop hook checks report structure and build freshness, then
requests a review against R0–R9. Perform the same checks explicitly when the
host does not support hooks, and report unresolved items at handoff.


### Write the report in `report.md`

Each `report.md` is the narrative source of its report; HTML fragments it
includes are the only other authored input, and every result is computed from
its declared inputs. There is no hand-written data file. The page renders the
Markdown top to bottom, and its `##` headings form the section navigation.

- **Front matter** names the report: `title` (default: the folder name),
  `subtitle`, `status`, `summary` (required), and `inputs` (below), which declares
  every artifact directory the report reads through an exact run URI.
- **Metric cards** come from `metric(label, value, detail="", fmt=None)` calls
  in a `python exec` block.
- **Values in prose** use `{{ expression }}` or `{{ expression:.3f }}`,
  evaluated in the exec namespace at that point of the document. Write
  "residual {{ final:.3f }}", never a typed number. The build manifest lists the
  decimals and percentages still typed in prose, by line (`typed_numbers`);
  turn each result into a `{{ }}` value and leave only design constants, such
  as a gate threshold, typed.
- **Findings** are `!!! finding <status> "Title"` blocks with status
  `tentative`, `supported`, `contradicted`, or `superseded`. Their id is
  `finding-<slug of the title>`, so keep titles stable: state the claim
  qualitatively ("The adaptive threshold breaks down earlier than the oracle"),
  never with a result number, and give the numbers in the body as `{{ }}`
  values, because a changed number would change the id and break links to the
  finding.
- **Figures** are Markdown images, `![Title](path "Caption"){#fig-id}`; a
  paragraph of only images becomes a figure grid, a `.plotly.json` file an
  interactive Plotly figure, and a video (`.mp4`, `.webm`, `.mov`) a video card
  that plays on screen and opens in a player with frame steps and scrubbing.
  Use a video for behavior over time (an optimization, a rollout, temporal
  artifacts), not for what one still image shows. Matplotlib figures created in
  `python exec` blocks become figure cards too (`num="<slug>"` gives a stable
  `fig-<slug>` id; `caption(text)` sets the caption).
- **Diagrams** are Graphviz fences, and only where they explain structure (see
  Diagrams); **cross-report links** use `report:<slug>#anchor`; **tables** are
  pipe tables; everything else is ordinary Markdown.

## Method diagrams

For neural-network architecture figures, copy
[../assets/model_graph.py](../assets/model_graph.py) to `tools/model_graph.py`
and add `torchview` and `graphviz` Python dependencies plus the native Graphviz
binary. Pass `model_dot(...)` to Folio's `graph(...)` helper, using the same
model and scientifically meaningful configuration as the experiment. Show the
component depth a paper would use, not every primitive operation.
