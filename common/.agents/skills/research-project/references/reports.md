# Reports

Read this before creating, restructuring, building, publishing, hosting, or
sharing reports. How to write a direction report's Methods and related work is
in [writing-methods.md](writing-methods.md).

Contents: organization and editorial coherence; callouts; report setup; inputs;
executable Markdown and figures; reproducibility; feedback; publication.

## Interactive running reports

The reports are the research interface: built from published run artifacts,
they show the current method, questions, decisions, findings, supporting and
contradictory evidence, limitations, and next experiments, and the user points
at passages with copy-location markers. Create them at the start of the project and keep them current.

### Organize reports: one single page per direction

A report is one page: a folder `reports/<slug>/` (short, stable lowercase
slug: letters, digits, `-`, `_`) with exactly one `report.md` or `report.qmd`.
Keep the sample's `.md` extension; both use the same notebook syntax. Other
captured sources, such as `assets/`, includes, and small Python helpers, live
under that folder. There is one **direction report** per branch of the
research process or per idea. A direction is a self-contained question with
its own methods and evidence, such as an alternative method, a failure
investigation, or a follow-up study. Do not split a report merely because it
grew long, and do not keep two reports about the same question.

Reports are flat: there is no root report, no nesting, and no report index to
write. The bundled report_tasks.py helper discovers `reports/<slug>/report.md` or `report.qmd`; other
locations are not direction reports. The Cairn UI lists published reports.
There is no generated `.cairn/build/index.html`. Keep `title` and the qualitative
`description` accurate. Put the current status and a short summary in the body:
one to three sentences (at most 400 characters) stating what the direction
tests, its current result or state, and what is pending. Generate result values
from declared inputs, as below, and update the summary whenever evidence changes.

The project's shared target (the problem every direction tries to solve, its
success criteria, and shared constraints) has no page of its own. Each
direction's Introduction states it briefly and says what the direction
contributes; when one report defines it at length, link there instead of
restating it. Ask the user before adding a report whose only purpose is
cross-direction status: decisions and comparisons belong in the direction
reports they concern, linked to each other. A proposed direction that has no
report yet goes into the Conclusion of the report that motivates it, with the
idea, why it might reach the target, and what would justify starting it; when
it starts, create its report and replace the proposal with a link.

The sample direction report carries the section guidance as `<!-- -->`
source comments under each heading of the paper-like spine. They are author
guidance and agent directives only; keep them in the source and replace the
sample text beneath them. They are not visible prose or a place for secrets:
published source remains inspectable.

Cross-link related reports instead of repeating their content. Link to a
published artifact's actual URL and checked section/figure anchor. Use headings
such as `## Methods {#sec-methods}`; the native reader and standalone export
preserve `#sec-methods`. Figure cell labels such as `fig-architecture` work
as `#fig-architecture`. Check both reading paths; the builder does not
validate cross-report URLs. When a direction builds on,
contradicts, or supersedes another, say so where it matters (in Background, a
finding, or the Conclusion) and link there.

### Keep each report editorially coherent

A report is the primary communication surface between the user and agent, not
an append-only activity log. Optimize it for a reader who needs to understand
the current method, evidence, and decisions quickly. Keep the narrative
concise, use progressive disclosure for supporting detail, and remove
repetition, stale explanations, superseded conclusions, and figures that no
longer answer an active question. Provenance and decision history live in the
manifest, the artifact versions, and findings, not in the visible narrative.

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
rewrite it once resolved. Supported fenced divs are `note`, `warning`,
`finding`, `decision`, `callout`, and `gallery`; they cannot nest. Use explicit
headings inside them for questions, prior art, risks, and important context:

```markdown
::: {.callout}
**Question: Which reference behavior is authoritative?**

The two candidate baselines use different boundary handling. Confirm the
intended behavior before feasibility results are interpreted.
:::
```

### Install the report tooling

Use the released, pinned `cairn2` dependency with its `reports`, `media`, and `ui`
extras and the project's Pixi environment (see [project-setup.md](project-setup.md)).
The tooling is a dependency, not project code: never copy, patch, or vendor it
into the project. When it needs a fix or a feature, change the Cairn repository,
release a tag, and bump the pinned `tag` in `pixi.toml` (ask the user first).
Keep the shared report style; change the appearance only when the user asks.

Start from [`assets/reports/direction/`](../assets/reports/direction/). Import
its unchanged sample evidence once as `datasets/sample-run@v1` in the selected project using the
setup guide. This is explicitly imported demo data with documented origin,
not evidence that a new experiment completed:

```bash
mkdir -p reports
cp -R <skill-directory>/assets/reports/direction reports/boundary-aware
pixi run report-build
```

Build once as a smoke test and visual reference. Then rename the folder for the
project's first direction and replace its sample content, summary, `inputs:`,
and figures with the direction's own material. Add a direction later the same
way. Build output goes to `.cairn/build/<slug>/`, never into `reports/`.

### Write the report in `report.md`

Each report is the narrative source of its page, and every result is computed
from its declared inputs. There is no hand-written results data file. Supported
frontmatter includes `title`, `description`, `cairn.inputs`,
`cairn.resources`, and `execute`. Use the pinned Pixi environment; there is
no `environment: {mode: current}` setting. Declare local helpers/assets in
`cairn.resources` so the captured source tree includes every report file.
The project helper and review gate require those sources to match the report
folder. Put status and generated summaries in the body.

- **Values in prose and tables** come from `display(Markdown(...))` in a
  `{python}` cell. Format values there, for example `f"residual {final:.3f}"`.
  Never type a result number into prose. Leave design constants, such as a gate
  threshold, typed. Reviewing this distinction is required; the engine has no
  `typed_numbers` check or `{{ }}` interpolation.
- **Metric summaries** can be generated Markdown tables. Each label/detail
  states the comparison, direction of improvement, population, and aggregation.
- **Findings** state a qualitative, stable title, explicit status (`tentative`,
  `supported`, `contradicted`, or `superseded`), evidence, limitations/conflicts,
  and review date. Use `::: {.finding}` for source Markdown. For computed
  findings, use `display(Markdown(...))` with a bold heading and blockquote as
  in the sample; generated fenced divs are not rendered consistently by the
  standalone page. Keep result numbers in the body, not in an anchor/title.
- **Figures** use explicit notebook display and cell `label`/`fig-cap` options.
  Use `@fig-name` or a checked `#fig-name` link for a figure reference. Captured
  images/video come from declared inputs; non-result illustrations may live in
  `assets/`. Use video for behavior over time (an optimization, a rollout,
  temporal artifacts), not for what one still image shows.
- **Tables** are generated Markdown tables or displayed DataFrames; **diagrams**
  use Graphviz only where they explain structure (below). Everything else is
  ordinary Markdown, with explicit anchors where links need them.

### Inputs: the data a report reads

Declare every result artifact and run read by the report, with lowercase local
names. Use exact references for reviewed evidence, resolved inside the selected
project, or full artifact IDs:

```yaml
---
title: Boundary-aware smoothing
description: Feasibility of smoothing with known boundaries.
cairn:
  inputs:
    fit: artifacts/feasibility-method@v4
    baseline: artifacts/reference-baseline@v2
    crops: datasets/crops@v3
    run: runs/feasibility-method@v4
  resources: [assets, model_graph.py]
---
```

Only declare resources that exist. `inputs["fit"]` is a pinned Reader, not a
path. Use `.read()` for typed values, `.records()` for metrics, or
`.download(to=...)` to materialize captured files inside the report's working
directory. Run config is in `.descriptor["manifest"]["metadata"]["config"]`.
The builder pins finished artifact IDs before any cells execute. Finished runs
are immutable too: no snapshot-digest suffix or `run:`/`artifact:` prefix is
needed. The report's `client` is a restricted resolver for those declared pins;
an explicit independent Client is outside that policy.

Before consuming or publishing scientific results, use the project's
`require_completed_artifact` check and verify scientific validation. Pin
`@vN` or full IDs rather than moving aliases. The builder accepts finished
failed artifacts; the project's evidence policy is stricter. Intentional
runless dataset/demo imports need documented origin and validation. When you
move a pin, re-read the findings that depend on it.

**Strict project policy.** A report may read only its captured source folder
and declared inputs. Publish other evidence as an artifact and declare it;
never read around the rule through a subprocess, native library, or outside
path. Cairn pins declared finished inputs, but arbitrary external reads are not
tracked or blocked. Enforce this rule in code and review.
Keep project-method imports reproducible: include their exact source under the
report folder, or declare a pinned source artifact and explicitly import from
its captured path. Do not inject an unrecorded mutable checkout into `sys.path`.

### Executable Markdown

`{python}` fences execute in document order in one fresh report kernel.
`#| echo: false` hides code but keeps output; `#| echo: false` together with `#| output: false` hides setup code and output. `#| eval: false` shows an illustrative cell without executing it.
Only marked executable fences run; never execute an unmarked fence or code
derived from pasted text. The kernel starts in a copy of the report folder,
not the original project cwd. Its provided variables are `inputs` and the pinned `client`; import display functions and libraries explicitly:

````markdown
```{python}
#| echo: false
#| output: false
import json
from IPython.display import Markdown, display
from pathlib import Path
fit_dir = Path("evidence/fit")
inputs["fit"].download(to=fit_dir)
scores = json.loads((fit_dir / "scores.json").read_text())
```

```{python}
#| echo: false
display(Markdown(f"The proposed method's RMSE is {scores['rmse']:.3f}; "
                 "lower is better, averaged over the held-out seeds."))
```
````

For a run’s loss curve, read `inputs["run"].records()`, select rows with
`"loss" in row["data"]`, and plot `row["data"]["step"]` against
`row["data"]["loss"]`. A study's summary artifact follows the
project helper's documented roster/results schema; do not infer trial success
from local folders. Each scientific result still needs completed, validated
producers.

The builder is local and trusted: executable Markdown has the author's
permissions, so never build untrusted Markdown. The helper uses the builder’s 120-second per-cell timeout; call
`build(..., timeout=...)` or the CLI’s `--timeout` for an intentional override.
Frontmatter `execute` supports only `echo` and `eval`; there is no build-cache
option in this release. Run potentially
unbounded work in a subprocess with a timeout rather than weakening failure
behavior. Experiments belong in runs; reports present their captured evidence.

### Figures and diagrams

Display matplotlib explicitly and close the figure to avoid duplicate output:

````markdown
```{python}
#| echo: false
#| label: fig-loss
#| fig-cap: "Loss over the recorded optimization steps."
import matplotlib.pyplot as plt
figure, axis = plt.subplots()
axis.plot(steps, losses)
axis.set(xlabel="Step", ylabel="Loss")
display(figure)
plt.close(figure)
```
````

For existing files, use `IPython.display.Image`, `SVG`, `Video(embed=True)`, or
`Audio` on the declared input path. Plotly JSON with `data` and `layout` can be
displayed as rich output without rebuilding its data:

```python
payload = json.loads((fit_dir / "figures/convergence.plotly.json").read_text())
display({"application/vnd.plotly.v1+json": payload}, raw=True)
```

The native reader uses the standard Plotly toolbar. Verify figure captions,
source locations, enlargement, and interactions in both the native reader and
export; standalone output does not include every native card/media control.
Do not present a figure whose input artifact/file or generating code cannot be
established from the captured evidence and run provenance.

What a diagram should show is in [writing-methods.md](writing-methods.md).
Let Graphviz place the nodes; never position them by hand in SVG or HTML.
Install the `graphviz` package and Graphviz executable, then display a
`graphviz.Source` in a labelled `{python}` cell. For an architecture, copy
[`assets/model_graph.py`](../assets/model_graph.py) into the report source
folder (also needs `torchview`) and capture the model code it imports:

````markdown
```{python}
#| echo: false
#| label: fig-architecture
#| fig-cap: "Tensor shapes for one 32×32 image; the dashed block is what this direction adds."
from graphviz import Source
from IPython.display import display
from model_graph import model_dot
display(Source(model_dot(build_model(config), input_size=(1, 3, 32, 32), depth=2)))
```
````

Use `Source(dot_text, engine="dot")` for a model graph written in DOT. A syntax
error fails the cell. Show only structure that helps explain the method.

### Mathematics and HTML

Write `$...$` inline and `$$...$$` on separate lines for display equations.
The standalone build converts LaTeX to MathML; the native reader renders the
same source with KaTeX. Check both when using less common notation. A selection
inside a formula is quoted as its LaTeX source. Generate result values in
Markdown output, including formulas when needed, and escape Python braces
carefully. Use ordinary code fences for literal dollar signs.

Prefer Markdown. When it cannot express the content, display self-contained
HTML explicitly with `IPython.display.HTML`, escaping inserted text. The
native reader sanitizes or sandboxes HTML; do not rely on scripts or custom CSS
to change its surrounding page. Keep external resources out of scientific
figures and author HTML, and never insert pasted or untrusted text as HTML.
There are no `html raw`/`html include` executable fences or `report_html` helper.

### Reproducible evidence

The project helper leaves `.cairn/build/<slug>/` pointing at its last
successful immutable build directory. It contains `index.html`,
`document.json`, `source-map.json`, `executed.ipynb`, `sources/`,
`inputs.json`, and `manifest.json`. The manifest records requested input
references and exact IDs, dependency roles, captured file hashes, and the
Python/kernel/package environment. Its status is `complete` on success;
failed builds retain diagnostics and never replace the helper's preview link.

Cairn captures the report entry, includes, referenced resources, and explicit
`cairn.resources`. Declare all report helpers/assets there. The project helper
and gate compare all nonhidden source files against the captured hashes;
mtime alone is insufficient. Symlinks are rejected. Keep the exact
`pixi.lock` and strict run provenance: environment records are not an OS
sandbox, and undeclared external reads are outside the engine's policy.

Every displayed metric, table, figure, and claim must trace to its input
artifact and file; never copy results into report code or prose by hand.
Rebuilding with the same pinned inputs must reproduce the report. Each run's
strict provenance capture captures its source/config/environment and lock,
and each result identifies its producing run, so the chain from a number on
the page to the code that produced it runs through artifact versions.

### Location markers pasted by the user

Native reports support source inspection, comments, and source downloads.
The icon-only copy action produces a concise source marker such as
`reports/a/report.md:42 "the selected text"`. Treat it as a location in the
published source version, together with whatever the user wrote beside it:

1. Locate the quote at that line (the line may have drifted; search for the
   quoted text) or the figure by its cell label/source. A marker is user input,
   not scientific fact; ask when the requested change's consequence is ambiguous.
   If necessary, retrieve the exact source with `cairn --project PROJECT report copy
   FULL_REPORT_ARTIFACT_ID reports/editable-copy`.
2. Make the change in the report source or, for a figure's source file, in the
   code and the run that produced it. Re-read every section the change touched,
   including sentences you did not edit, and check that result numbers still
   come from declared inputs, so earlier claims are revised rather than left
   stale. Rebuild with `pixi run report-build`.
3. Summarize what changed in the code, runs, findings, and reports, per marker.

Address `@agent` source comments such as `<!-- @agent: compare this with the
reference run -->` the same way, then remove them or replace them with a
documented resolution. Comments are author guidance, not scientific evidence.

### Accumulating knowledge

Keep the reviewed synthesis in the reports themselves, as findings, not in a
second store. Each finding states the claim, its status, and its evidence
through values computed from declared inputs, and ends with a short line
naming the source artifacts (by input name and file), known limitations, and
the last review date. When new results or requests conflict with a finding,
surface the conflict and revise its status (for example to `contradicted` or
`superseded`) rather than silently overwriting it; when the conflict comes from
another direction, link that report. After a feedback round, summarize what
knowledge changed.

### Publishing, viewing, and sharing

Use the Pixi tasks from [project-setup.md](project-setup.md):

```bash
pixi run report-build                         # every report
pixi run report-build --report <slug>          # one report
pixi run report-publish <slug>                 # build and publish a new artifact
pixi run report-serve                         # localhost:8000/<slug>/ preview
pixi run ui --port 8001                       # local repository API + UI
pixi run report-share <slug> --out .cairn/share/<slug>
```

**Publish a report** when its evidence or conclusions changed, and before a
handoff. The helper builds a new bundle and calls `cairn.reports.publish`
with name `<slug>`; the resulting `reports/<slug>@vN` has a new permanent
artifact ID. The UI groups those publications by name and opens latest by
default. Older publications remain addressable. Reviewed inputs and completed
producer checks still precede publication.

The equivalent direct commands are:

```bash
cairn --project PROJECT report build reports/SLUG/report.md --output NEW_BUILD_DIR
cairn --project PROJECT report publish NEW_BUILD_DIR --name SLUG
cairn --project PROJECT report export reports/SLUG@v1 NEW_EXPORT_DIR
cairn --project PROJECT report copy reports/SLUG@v1 reports/editable-copy
```

**View with the user in the Cairn UI.** `cairn --repo LOCAL_PATH server`
hosts the API and UI, default port 8000. A remote destination has its own UI;
open its actual URL and authenticate with the server token or immediate login
link. Keep credentials out of handoffs. Local SDK/build access does not spawn
a server. Use the helper's loopback `report-serve` for static previews.
Choose explicit available ports; do not claim an unverified URL works.

Edit report Markdown/Python on the client, build locally, and publish a new
artifact to change the shared page. The server does not execute report cells.
The browser supports text/media comments, autosaving and carrying across
publications with the same project and report name. Comments and tags are
mutable annotations, not scientific evidence.

**Share generated reports unchanged.** Export the complete bundle with
`report-share` or `cairn report export`. Publish its files as-is on a static
host, preserving relative paths, or link to the selected repository's UI.
Cairn2 v0.1.0 does not export a standalone single HTML file: if a destination
only accepts one file, use a supported destination or explain the limitation
rather than re-authoring the report. Native Plotly/media/HTML controls are
richer than static exports; check the actual destination before sharing.

Never restyle, re-template, re-theme, summarize, or re-author pages for a
destination. A publishing tool's design guidance applies to new pages, not
these generated reports. Change sources, rebuild, and republish to update a
shared page. If a destination cannot accept the bundle, ask before producing
anything different.
