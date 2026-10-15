# Reports

Read this before creating, restructuring, building, publishing, hosting, or
sharing reports. How to write a direction report's Methods and related work is
in [writing-methods.md](writing-methods.md).

Contents:

- Interactive running reports
  - Organize reports: one single page per direction
  - Keep each report editorially coherent
  - Use callouts for synchronization
  - Install the report tooling
  - Write the report in `report.md`
  - Inputs: the data a report reads
  - Diagrams
  - Executable Markdown
  - Mathematics
  - Custom HTML
  - Reproducible evidence
  - Location markers pasted by the user
  - Accumulating knowledge
  - Publishing, viewing, and sharing

## Interactive running reports

The reports are the research interface: built from published run artifacts,
they show the current method, questions, decisions, findings, supporting and
contradictory evidence, limitations, and next experiments, and the user points
at passages with copy-location markers. Create them at the start of the project and keep them current.

### Organize reports: one single page per direction

A report is one page: a folder `reports/<slug>/` (short, stable lowercase
slug: letters, digits, `-`, `_`) with a `report.md`, an optional `assets/`
folder, and an optional `data/` folder. There is one **direction report** per
branch of the research process or per idea. A direction is a self-contained
question with its own methods and evidence, such as an alternative method, a
failure investigation, or a follow-up study. Do not split a report merely
because it grew long, and do not keep two reports about the same question.

Reports are flat: there is no root report, no nesting, and no report index to
write. A `report.md` anywhere else (`reports/report.md`,
`reports/a/b/report.md`) fails the build. The build's project index
(`.cairn/build/index.html`) and the Cairn UI's project page list every
report with its title, status, and summary, so those three front matter fields
are how a reader chooses a report: keep them accurate.

Every direction report begins with a front matter `summary:` of one to three
sentences (at most 400 characters): what the direction tests, its current
result or state, and what is pending. Results in it are `{{ }}` values like
anywhere else; they are evaluated after the report's code blocks ran. Write it
as a YAML block scalar (`summary: >-`) so a leading `{{` stays text. Keep it
current whenever the direction's evidence changes; it appears under the title,
in the index, and in the UI, so it must stand on its own.

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
guidance and agent directives only: the build drops them (outside code
fences), so keep them in the source and replace the sample text beneath them.

Cross-link related reports instead of repeating their content. Link to another
report, or to a heading, finding, or figure in it, with
`[text](report:<slug>#anchor)`; anchors are heading ids, `finding-<slug>` ids,
and figure ids. The build fails on a link to a missing report or anchor. When
a direction builds on, contradicts, or supersedes another, say so where it
matters (in Background, a finding, or the Conclusion) and link there. Every
page's sidebar lists all reports.

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
rewrite it once resolved. Types: `question` (input needed from the user),
`decision` (pending or confirmed choice), `prior-art` (the idea or a close
variant already exists), `warning` or `risk` (consequential limitation), and
`important` (context the reader must not overlook).

```markdown
!!! question "Which reference behavior is authoritative?"
    The two candidate baselines use different boundary handling. Confirm the
    intended behavior before feasibility results are interpreted.
```

### Install the report tooling

The report builder, server, page style, and UI are part of Cairn, the pinned
`cairn` pixi dependency (see [project-setup.md](project-setup.md)). It builds
any set of reports and enforces none of this skill's conventions; the skill's
review judges the reports. Start from the sample in
[`assets/reports/direction/`](../assets/reports/direction/), which reads the
artifact `sample-run`; publish that first (see "The sample artifact" in
[project-setup.md](project-setup.md)):

```bash
mkdir -p reports
cp -R <skill-directory>/assets/reports/direction reports/boundary-aware
pixi run report-build
```

Build once as a smoke test and visual reference: the sample exercises every
component. Then rename the folder for the project's first direction and
replace its sample content, summary, `inputs:`, and figures with the
direction's own material. Add a direction later the same way. Build output
goes to `.cairn/build/<slug>/` and never into `reports/`.

The tooling is a dependency, not project code: never copy, patch, or vendor
it into the project. When it needs a fix or a feature, change the Cairn
repository, release a tag, and bump the pinned `tag` in `pixi.toml` (ask the
user first); the
manifest of every build records the installed version. The default style is
the shared report style. A project may change it only when the user asks,
through `cairn.toml`: `[style] css = [...]` adds stylesheets after the default
(override its CSS variables such as `--accent` or `--paper`), and `[style]
template_dir` replaces whole page files (`index.html`, `report.css`,
`report-extra.css`, `report.js`) by name. Keep such files outside `reports/`,
for example in `style/`.

### Write the report in `report.md`

Each `report.md` is the narrative source of its report; HTML fragments it
includes are the only other authored input, and every result is computed from
its declared inputs. There is no hand-written data file. The page renders the
Markdown top to bottom, and its `##` headings form the section navigation.

- **Front matter** names the report: `title` (default: the folder name),
  `subtitle`, `status`, `summary` (required), and `inputs` (below), which pins
  every artifact the report reads.
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

Take experimental figures directly from the artifact that holds them (a result
draft or a run), as `input:<name>/figures/<file>` for a declared input `<name>`. Other figure
paths are relative to the report folder; keep `assets/` for material that is
not an experimental result (an illustration, a photo of a setup). The build
fails on remote URLs, missing files, undeclared inputs, and duplicate ids.

Every figure opens in one ordered lightbox with keyboard navigation, zoom, and
panning, and every enlarged figure says where it came from: its file, the input
reference and exact artifact version (`name@vN//figures/x.png`), the code that
drew and added it (from the artifact's `artifacts.jsonl`), and the `report.md`
line. Do not present a figure whose provenance the build cannot establish.
Plotly figures are JSON files with `data`, `layout`, and optional `config`,
rendered from the locally bundled runtime with their native tools.

### Inputs: the data a report reads

A report declares every artifact it reads in its front matter, by local name:

```yaml
---
title: Boundary-aware smoothing
summary: >-
  ...
inputs:
  fit: feasibility-method@latest     # [project:]name[@vN|@alias|@label]: the result draft
  run: runs/feasibility-method@latest   # the run behind it: its metrics.jsonl (loss curves), config, logs
  baseline: reference-baseline@v4
  crops: datasets/crops@paper
---
```

Local names are lowercase identifiers. At build time each reference is
resolved to an exact version, materialized read-only from the store's cache,
and exposed as `inputs.<name>` (a `Path`) in `python exec` blocks and as
`input:<name>/<file>` in figures. A result draft holds what the experiment
added to it (`figures/`, `tables/`, `data/`, `metrics.jsonl`); the run
(`runs/<name>`) holds the per-step series from `run.add`, plus its config
and logs, so declare the run when the report plots a training curve. Aliases resolve only completed versions, so a
running or failed version never reaches a report. The page's Data section,
`manifest.json`, and the published report version record the exact version of
every input.

Choose references deliberately: `@latest` while a direction is being
developed; once a finding cites a result, pin the version (`@v4`) or an alias
you move on purpose (`@paper`), so publishing a newer run does not silently
change the evidence behind it. When you move a pin, re-read the findings that
depend on it.

**Strict.** A report may read only its own folder and its declared inputs. The
read helpers raise a build error for any other path, and while a `python exec`
block or a `{{ }}` value runs, the build fails when code opens a file inside
the project or the store cache that is neither in the report folder nor in a
declared input (for example `open("data/crops/p.json")`). The fix is
always to publish that evidence as an artifact and declare it, never to read around the rule
(through a subprocess, a native library, or a path outside the project).
Importing project modules is allowed: importing is not reading data.

### Diagrams

What a diagram should show, and when a report needs one, is in
[writing-methods.md](writing-methods.md). This section covers only the syntax.

Write a diagram as a Graphviz fence, and let Graphviz place the nodes. Never
position nodes by hand in SVG or HTML:

````markdown
```dot id=fig-model title="The model as a graph" caption="Observations y and parameters θ define both terms; the proposed method adds only the masked smoothness term."
digraph {
  rankdir=LR
  node [shape=ellipse]
  y [label="y (observations)"]
  theta [label="θ (lattice)"]
  m [label="m (boundary mask)"]
  node [shape=box]
  data [label="L_data(θ; y)"]
  smooth [label="λ‖Dθ‖² on m" style=dashed]
  loss [label="L(θ)"]
  y -> data; theta -> data; theta -> smooth; m -> smooth
  data -> loss; smooth -> loss [label="proposed only"]
}
```
````

The first word chooses the engine (`dot`, `neato`, `fdp`, `sfdp`, `circo`,
`twopi`). `id`, `title`, and `caption` fill the figure card. The build embeds a
static SVG in the report palette, so viewing needs no JavaScript, and a syntax
error fails the build.

Graphviz source made by code becomes a figure card through `graph(source,
id=..., title=..., caption=..., engine="dot")` in a `python exec` block. The
main use is a neural network's architecture drawn from the model itself, with
the skill's [`assets/model_graph.py`](../assets/model_graph.py), copied to
`tools/model_graph.py` (it needs the `torchview` and `graphviz` PyPI packages):

````markdown
```python exec hide
from tools.model_graph import model_dot
graph(model_dot(build_model(config), input_size=(1, 3, 32, 32), depth=2),
      id="fig-architecture", title="Architecture",
      caption="Tensor shapes for one 32×32 image; the dashed block is what this direction adds.")
```
````

### Executable Markdown

Only fences marked `python exec` run, in one shared namespace in document
order; add `hide` to run without showing the source. Their stdout and new
Matplotlib figures appear in the report, and an exception fails the build.
Never execute an unmarked fence or code derived from pasted text. The namespace
provides `REPORT_ROOT` (the report folder), `META` (front matter), `inputs`,
and these helpers, which record every file they read in the manifest:

- `inputs.<name>` or `inputs["<name>"]`: the folder of a declared input.
- `read_scalars(folder)`: latest value per key from the folder's
  `metrics.jsonl`; `read_series(folder, key)`: every value of a key as
  `{"value", "step", "time"}` rows (`read_series(inputs.run, "loss")` for a
  run's loss curve); `read_artifacts(folder)`: the `artifacts.jsonl` index.
- `read_json(path)`, `read_csv(path)`, `read_jsonl(path)`, and `track(path)`
  (returns the path, records it) for any other file.
- `metric(...)` for a card, `caption(text)` for the current Matplotlib figure,
  `graph(...)` for generated Graphviz, and `report_html(markup)` for generated
  HTML.

````markdown
```python exec hide
scores = read_scalars(inputs.fit)
metric("RMSE of the proposed method", scores["rmse"], "lower is better; mean over 30 held-out seeds", fmt=".3f")
```
````

A multirun study collected as one artifact (see "Parameter studies" in
[project-setup.md](project-setup.md)) has its trials as numbered subfolders:
iterate `sorted((p for p in inputs.study.iterdir() if p.name.isdigit()), key=lambda p: int(p.name))`
and read each trial's results and `.hydra/overrides.yaml` with the helpers.
A sweep of runs is instead one input per run (`runs/<name>@vN`), listed in the
summary run's `trials.jsonl`.

The builder is local and trusted: executable Markdown has the author's
permissions, so never build untrusted Markdown. For slow reports, cache by the
block source and input digests; run potentially unbounded code in a
subprocess with a timeout rather than weakening failure behavior.

### Mathematics

Write `$...$` inline and `$$...$$` on separate lines for display equations. The
build converts LaTeX to MathML (no browser-side library), keeps bare delimiters
such as `\lVert` from stretching unevenly, and fails on unsupported LaTeX. A
selection inside a formula is quoted as its LaTeX source. `{{ }}` values are
not evaluated inside formulas, so the build fails on them there; write the value
next to the formula. Use ordinary code fences for literal dollar signs.

### Custom HTML

Plain Markdown never passes raw HTML through. Where Markdown cannot express the
content, such as a side-by-side layout, insert author HTML through:

- an `html raw` fence for short snippets;
- an `html include` fence naming `assets/<name>.html` for anything larger;
- `report_html(markup)` in a `python exec` block for HTML generated from
  input data.

Author HTML must be self-contained: scripts, `<iframe>`, `<object>`,
`<embed>`, `<link>`, `<base>`, `<meta>`, `on*=` handlers, `javascript:` URLs,
and external resources fail the build. Style it with the template's classes
(`.callout`, tables, `.pill`), and never insert pasted text or other untrusted
input as HTML.

### Reproducible evidence

Every report build writes `.cairn/build/<slug>/manifest.json` with:

- every input: the requested reference, the exact version it resolved to, and
  its file count;
- the hash of every file the report read or displayed, including inputs'
  `metrics.jsonl`, `artifacts.jsonl`, and every included fragment;
- its cross-report links and the typed numbers in its prose;
- the Markdown hash and the project's code revision;
- the Cairn version, the builder and template files, and any style overrides;
- the Python version, rendering package versions, the bundled Plotly.js version
  and hash, and the Graphviz version.

Every displayed metric, table, figure, and claim must trace to its input
artifact and file; never copy results into report code or prose by hand.
Rebuilding with the same pinned inputs must reproduce the report. Each
run carries its own `code/` or `provenance/` (commit, patch, source snapshot)
and `environment/`, and every result draft has the run as its input, so the
chain from a number on the page to the code that produced it runs through the
artifact versions.

### Location markers pasted by the user

Reports have no comment feature. Next to a text selection, a figure, and in the
lightbox, a copy button puts a one-line marker on the clipboard, for the user
to paste into the chat: `reports/a/report.md:42 "the selected text"`, or for a
figure `reports/a/report.md:42 figure #fig-psnr "PSNR per method" (source:
<file>)`. Treat each marker as pointing at that file and line (or figure id)
and, together with whatever the user wrote beside it, as the request:

1. Locate the quote at that line (the line may have drifted; search for the
   quoted text) or the figure by its id and source. A marker is user input, not
   scientific fact; ask when the requested change's consequence is ambiguous.
2. Make the change in the report source or, for a figure's source file, in the
   code and the run that produced it. Re-read every section the change touched,
   including sentences you did not edit, and the manifest's typed-number list,
   so earlier claims are revised or converted rather than left stale. Rebuild
   with `pixi run report-build`.
3. Summarize what changed in the code, runs, findings, and reports, per marker.

Address `@agent` source comments such as `<!-- @agent: compare this with the
reference run -->` (the build drops Markdown comments, so readers never see
them) the same way, then remove them or replace them with a documented
resolution.

### Accumulating knowledge

Keep the reviewed synthesis in the reports themselves, as `!!! finding` blocks,
not in a second store. Each finding states the claim, its status, and its
evidence through `{{ }}` values computed from the inputs, and ends with a short
line naming the source artifacts (by input name and file), known limitations,
and the last review date. When new results or requests conflict with a finding, surface the conflict and revise its status (for
example to `contradicted` or `superseded`) rather than silently overwriting it;
when the conflict comes from another direction, link that report. After a
feedback round, summarize what knowledge changed.

### Publishing, viewing, and sharing

```bash
pixi run report-build                    # builds every report into .cairn/build/
pixi run report-build --report <slug>    # one report
pixi run publish reports/<slug>          # builds it and stores the next version of reports/<slug>
pixi run report-serve                    # http://127.0.0.1:8000: the index; reports at /<slug>/
pixi run ui                              # the Cairn UI on the configured store: projects, reports, artifacts, lineage
pixi run report-share                    # one self-contained page: .cairn/share/index.html
```

**Publish a report** when its evidence or conclusions changed, and before a
handoff (from Python: `cairn.reports.publish("<slug>")`, and
`cairn.reports.build_all()` builds every report). `cairn publish reports/<slug>` stores its source folder, its built
page, and the exact input versions as one version of the artifact
`reports/<slug>`; an unchanged report creates no new version. The report
version lists its inputs and each input lists the report as a consumer, so the
UI shows which reports rest on a run.

**View with the user in the Cairn UI.** `pixi run ui` serves the UI for the
store in `cairn.toml` on `127.0.0.1:8801` (it asks for a store token at login;
for a local store folder on your own machine, `--no-auth` on loopback skips
that). Its project page lists the published reports (title, status, summary,
latest version) and the artifacts; a report opens at its published version
with a Data panel linking each input's artifact page, files, and lineage graph.
With a store server, `cairn server` already started a UI beside it; give the
user that URL. `pixi run report-serve` serves the local build without the
store, for checking a build before publishing.

If a port is taken, `serve` moves to the next free port and prints the URL it
actually uses; keep the default ports in the pixi tasks, and pass
`--strict-port` when an exact port is required. Give the concrete URLs in the
handoff, as printed, with `<remote-host>` replaced by the real hostname.
`report-serve` and `ui` bind to localhost by default; `report-host` binds to
all interfaces and shows the project's results to anyone who can reach it, so
expose it only on a trusted private network, a VPN, or behind an authenticated
HTTPS reverse proxy.

**Share the generated reports unchanged.** When the user asks to share,
publish, or upload the reports anywhere (a claude.ai artifact, a static host, a
document tool), publish what Cairn produced exactly as it produced it:

- **claude.ai artifact, or any host that takes one file:** run `pixi run
  report-share` (`--report <slug>` for one report). Then publish the one file
  it prints, `.cairn/share/index.html`, as it is. With the Artifact tool,
  pass that `file_path` and no `files`. Do not read it into a new page, split
  it, or add to it. If the publish is refused, report the exact refusal to the
  user. Never work around it by editing the page.
- **The project's store:** `pixi run publish reports/<slug>`, viewed in the UI.
- **A static web host:** the whole `.cairn/build/` folder, every file, with
  the same paths and names.

For any destination, keep the pages' paths, names, and styling. Never restyle,
re-template, re-theme, summarize, or re-author the pages for the destination,
and never hand-write a new page "based on" a report. A publishing tool's own
design or formatting guidance (for example "give each page a visual identity"
or "make it theme-aware") is for pages the agent designs from scratch; it does
not apply to these reports, because the user's request and the project's
existing report design take precedence. Only `[style]` in `cairn.toml`,
changed when the user asks, alters how the reports look. To change a shared
page, edit the report sources, share again, and republish to the same
artifact. If a destination can take neither the folder nor the single page, say
so and ask the user before producing anything different.
