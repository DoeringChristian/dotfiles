# Reports

Read this before creating, restructuring, building, hosting, or sharing reports. How to write a direction report's Methods and related work is in [writing-methods.md](writing-methods.md).

Contents:

- Interactive running report
  - Organize reports: one overview, one report per direction
  - Keep each report editorially coherent
  - Use callouts for synchronization
  - Install the report tooling
  - Write the report in `report.md`
  - Diagrams
  - Executable Markdown
  - Mathematics
  - Custom HTML
  - Reproducible evidence
  - Comments
  - Accumulating knowledge
  - Hosting and safety
  - Remote runs and the hub

## Interactive running report

The reports are the research interface: generated from Hydra runs, they show
the current method, questions, decisions, findings, supporting and
contradictory evidence, limitations, and next experiments, and they collect the
user's comments. Create them at the start of the project and keep them current.

### Organize reports: one overview, one report per direction

A report is a folder with a `report.md` and an optional `assets/` folder;
cairn-report builds the folder tree into one site. The project has one
**overview**, the root report `reports/report.md`, served at `/`, and one
**direction report** per branch of the research process or per idea, as a
child folder `reports/<slug>/report.md` (short, stable lowercase slug), served
at `/<slug>/`. A direction is a self-contained question with its own methods and
evidence, such as an alternative method, a failure investigation, or a
follow-up study. Do not split a report merely because it grew long, and do not
keep two reports about the same question. Do not nest further levels unless the
user asks for them.

Every direction report begins with a front matter `summary:` of one to three
sentences (at most 400 characters): what the direction tests, its current
result or state, and what is pending. Results in it are `{{ }}` values like
anywhere else; they are evaluated after the report's code blocks ran. Write it
as a YAML block scalar (`summary: >-`) so a leading `{{` stays text. Keep it
current whenever the direction's evidence changes. The direction page shows it under its title,
and the overview's direction cards quote it, so it must stand on its own. Every
direction page links back to its card in the overview automatically.

The overview does not follow the paper structure. It has exactly three
sections, in this order:

1. `## Introduction`: the general target the whole project pursues, the one
   problem every research direction tries to solve. State why it matters, the
   success criteria all directions are judged by, and the constraints they
   share. It is the jumping-off point for every direction: each direction's own
   Introduction links to it (`report:/#introduction`) and builds on it
   instead of restating it. Change it only when the project's goal changes.
2. `## Status`: a status report across directions for someone deciding what to
   do next: which directions are promising, stalled, contradicted, or finished,
   where they agree or conflict, and the next decision (in a `decision` or
   `question` callout). It ends with **proposed directions** that have no
   report yet, each with the idea, why it might reach the target, and what
   would justify starting it. It cites direction findings with links and keeps
   the numbers in the direction reports. Status is a summary, but the numbers
   rule still holds: a result it states (a rate, a threshold where a method
   breaks, a comparison) comes from a `{{ }}` value computed from run files or
   is replaced by a link to the finding that holds it; never type it.
3. `## Research directions`: a ``` ```reports ``` ``` fence that renders one card
   per direction (title, status, summary, finding counts, link). An empty fence
   lists every direction; list slugs, one per line, to choose and order them.
   Directions are built before the overview.

The sample overview and direction reports carry this guidance as `<!-- -->`
comments under each heading, and the direction sample does the same for every
section of the paper-like spine. Comments are author guidance and agent
directives only: the build drops them (outside code fences), so keep them in
the source and replace the sample text beneath them. When a direction is
proposed in Status and then started, create its report and remove it from the
proposals.

Cross-link related reports instead of repeating their content. Link to another
report, or to a heading, finding, or figure in it, with
`[text](report:<slug>#anchor)`; the overview is `report:/`, and anchors are
heading ids, `finding-<slug>` ids, and figure ids. The build fails on a link
to a missing report or anchor. When a direction builds on, contradicts, or
supersedes another, say so where it matters (in Background, a finding, or the
Conclusion) and link there. Every report's sidebar lists the overview first and
every direction beneath it, so the overview is one click away from any page.

### Keep each report editorially coherent

A report is the primary communication surface between the user and agent, not
an append-only activity log. Optimize it for a reader who needs to understand
the current method, evidence, and decisions quickly. Keep the narrative
concise, use progressive disclosure for supporting detail, and remove
repetition, stale explanations, superseded conclusions, and figures that no
longer answer an active question. Provenance and decision history live in the
manifest, run outputs, findings, and comment log, not in the visible narrative.

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

The report builder, server, page style, and run logger are the `cairn-report`
package (<https://github.com/DoeringChristian/cairn-report>), a pinned pixi
dependency (see [project-setup.md](project-setup.md)). It builds any report tree and enforces none of this
skill's conventions; the skill's review judges the reports. Start the reports from the samples in
[`assets/reports/`](../assets/reports/):

```bash
mkdir -p reports
cp <skill-directory>/assets/reports/report.md reports/report.md            # the overview
cp -R <skill-directory>/assets/reports/direction reports/boundary-aware     # a sample direction
```

Add a direction later by copying `assets/reports/direction` to
`reports/<slug>`. Build once as a smoke test and visual reference: the sample
direction exercises every component. Then rename the direction folder and
replace its sample content, summary, and `assets/` with the direction's own
material. Replace the sample overview text at the same time: its `report:` links
name the sample slug, and the build fails on links to a renamed report. Build
output goes to `generated/reports/` and never into `reports/`.

Create `cairn-report.toml` with the text the Copy button puts before the
comments it copies, so pasted comments arrive with their handling instructions:

```toml
[page]
copy_preamble = """
Please address these report comments. For each one, locate its quote first,
falling back to its line or target; make the requested change, or ask me if its
consequence is ambiguous. Then run `pixi run report-build`, re-read every
section you changed, and summarize what changed in the code, runs, findings,
and reports. I clear the comments in the browser once they are handled.
"""
```

The tooling is a dependency, not project code: never copy, patch, or vendor
it into the project. When it needs a fix or a feature, change the
`cairn-report` repository, release a tag, and bump the pinned `tag` in
`pixi.toml`; the manifest of every build records the installed version and
commit. The default style is the shared report style. A project may change it
only when the user asks, through `cairn-report.toml`: `[style] css = [...]`
adds stylesheets after the default (override its CSS variables such as
`--accent` or `--paper`), and `[style] template_dir` replaces whole page files
(`index.html`, `report.css`, `report-extra.css`, `report.js`) by name. Keep such
files outside `reports/`, for example in `style/`.

### Write the report in `report.md`

Each `report.md` (the overview or a direction) is the narrative source of its
report; HTML fragments it includes are the only other authored input, and
every number is computed from run files. There is no hand-written data file. The page renders the
Markdown top to bottom, and its `##` headings form the section navigation.

- **Front matter** names the report: `title` (default: the folder name),
  `subtitle`, `status`, and, for a direction, `summary` (required).
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
  paragraph of only images becomes a figure grid, and a `.plotly.json` file an
  interactive Plotly figure. Matplotlib figures created in `python exec` blocks
  become figure cards too (`num="<slug>"` gives a stable `fig-<slug>` id).
- **Diagrams** are Graphviz fences, and only where they explain structure (see
  Diagrams); **cross-report links** use `report:`; the
  overview's **direction index** is a `reports` fence; **tables** are pipe
  tables; everything else is ordinary Markdown.

Take experimental figures directly from the run that wrote them, as
`run:<run-name>/figures/<name>.png` (the run's `latest`;
`run:<run-name>@<timestamp>/...` pins one run). These references work whether
the run is local, on a hub, or in MLflow. Other figure paths are relative to the
report folder; keep `assets/` for material that is not an experimental result.
The build fails on remote URLs, missing files, and duplicate ids. Use only
completed runs: the manifest records every run's `run.json` status, and the
review treats evidence from any other run as unsupported. The build copies each figure into the site by its resolved path
and records where it came from.

Every figure opens in one ordered lightbox with keyboard navigation, zoom, and
panning, and every enlarged figure says where it came from: an (i) toggle shows
its exact file, run, the code that drew and logged it (from `artifacts.jsonl`),
the run's commit and uncommitted patch, its MLflow or hub run when there is one,
and the `report.md` line. Do not present a figure whose provenance the build
cannot establish. Plotly figures are JSON artifacts with `data`, `layout`, and
optional `config`, rendered from the locally bundled runtime with their native
tools. The template implements these behaviors; verify them at desktop and
phone widths after changing it.

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
Never execute an unmarked fence or code derived from a comment. The namespace
provides `REPORT_ROOT` (the report folder), `PROJECT_ROOT`, `META` (front
matter), and these helpers, which record every file they read in the manifest:

- `run_dir(name, timestamp="latest")`: the resolved run directory (local, or
  downloaded from the hub or MLflow); the manifest records its status.
- `run_trials(study)`: every trial of a multirun study, with its `trial`
  number, `dir`, `overrides`, and `status`.
- `read_scalars(run)`: latest value per scalar name from `metrics.jsonl`.
- `read_json(path)`, `read_csv(path)`, `read_jsonl(path)`, and `track(path)`
  for any other file.
- `metric(...)` for a card and `report_html(markup)` for generated HTML.

````markdown
```python exec hide
run = run_dir("feasibility-method")
scores = read_scalars(run)
metric("RMSE of the proposed method", scores["rmse"], "lower is better; mean over 30 held-out seeds", fmt=".3f")
```
````

The builder is local and trusted: executable Markdown has the author's
permissions, so never build untrusted Markdown. For slow reports, cache by the
block source and input-file digests; run potentially unbounded code in a
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
- `report_html(markup)` in a `python exec` block for HTML generated from run
  data.

Author HTML must be self-contained: scripts, `<iframe>`, `<object>`,
`<embed>`, `<link>`, `<base>`, `<meta>`, `on*=` handlers, `javascript:` URLs,
and external resources fail the build. Style it with the template's classes
(`.callout`, tables, `.pill`), and never insert comment text or other untrusted
input as HTML.

### Reproducible evidence

Every report build writes a `manifest.json` next to each page
(`generated/reports/manifest.json` for the overview,
`generated/reports/<slug>/manifest.json` for a direction) with:

- the resolved run paths with their `run.json` status, and the selection rule;
- the hash of every file the report read or displayed, including each run's
  `run.json`, `metrics.jsonl`, `artifacts.jsonl`, provenance manifest and
  patch, and every included fragment;
- its cross-report links;
- the Markdown hash and the project's code revision;
- the `cairn-report` version and commit, and any style overrides;
- the Python version, rendering package versions, the bundled Plotly.js version
  and hash, and the Graphviz version.

Every displayed metric, table, figure, and claim must trace to its source run
and file; never copy results into report code or prose by hand. Rebuilding from
the same checkout and preserved outputs must reproduce the report. When run
data is too large to keep locally, document its external location and an
integrity digest.

### Comments

Readers comment by selecting text or clicking a figure's comment icon. Comments
are kept in that browser only, per report, with a stable `id`, `target` (such as
`figure:<id>`, `finding:<id>`, or `markdown:line:<n>`), the source `line` when
applicable, the selected `quote`, `text`, and `timestamp`. The page's Copy
button puts all of a report's comments on the clipboard as JSON, after the
`copy_preamble` from `cairn-report.toml` and the report's source path; the user
pastes them to the agent and clears them with the Clear button once handled.
There is no comment file in the project.

Handle comments the user pastes:

1. For each comment, locate its quote first, falling back to its line or
   target. Make the change, or ask when its consequence is ambiguous. A comment
   is user input, not scientific fact.
2. Re-read every section the change touched, including sentences you did not
   edit, and the manifest's typed-number list, so earlier claims are
   revised or converted rather than left stale. Rebuild with
   `pixi run report-build`.
3. Summarize what changed in the code, runs, findings, and reports, per comment
   id, so the user knows which comments to clear.

Address `@agent` source comments such as `<!-- @agent: compare this with the
reference run -->` (the build drops comments, so readers never see them) the
same way, then remove them or replace them with a documented resolution.

### Accumulating knowledge

Keep the reviewed synthesis in the reports themselves, as `!!! finding` blocks,
not in a second store. Each finding states the claim, its status, and its
evidence through `{{ }}` values computed from run files, and ends with a short
line naming the source runs or files, originating comment ids, known
limitations, and the last review date. When new results or comments conflict
with a finding, surface the conflict and revise its status (for example to
`contradicted` or `superseded`) rather than silently overwriting it; when the
conflict comes from another branch, link that report. After a feedback round,
summarize what knowledge changed.

### Hosting and safety

```bash
pixi run report-build  # builds every report
pixi run report-serve  # http://127.0.0.1:8000 (overview); directions at /<slug>/
pixi run report-host   # http://<remote-host>:8000
```

If the port is taken, for example by another project's report server, the
server moves to the next free port and prints the URL it actually uses; keep
8000 in the pixi tasks rather than editing them, and pass `--strict-port` when
an exact port is required. Give the concrete URLs in the handoff, as printed,
with `<remote-host>` replaced by the real hostname or address. The built site is
static and the server accepts no writes. `report-serve` is the safe local
default; `report-host` binds to all interfaces and shows the project's results
to anyone who can reach it, so expose it only on a trusted private network, a
VPN, or behind an authenticated HTTPS reverse proxy.

**Share the generated reports unchanged.** When the user asks to share,
publish, or upload the reports anywhere (the hub, a static host, a claude.ai
artifact, a document tool), publish what cairn-report produced exactly as it
produced it:

- **claude.ai artifact, or any host that takes one file:** run `pixi run
  report-share` (`cairn-report share --report <path>` for part of the tree).
  Then publish the one file it prints, `generated/share/index.html`, as it is.
  With the Artifact tool, pass that `file_path` and no `files`. Do not read it
  into a new page, split it, or add to it. If the publish is refused, report the
  exact refusal to the user. Never work around it by editing the page.
- **The hub:** `cairn-report push report`.
- **A static web host:** the whole `generated/reports/` folder, every file, with
  the same paths and names.

For any destination, keep the pages' paths, names, and styling. Never restyle, re-template, re-theme, summarize, or re-author the
pages for the destination, and never hand-write a new page "based on" a
report. A publishing tool's own design or formatting guidance (for example "give
each page a visual identity" or "make it theme-aware") is for pages the agent
designs from scratch; it does not apply to these reports, because the user's
request and the project's existing report design take precedence. Only
`[style]` in `cairn-report.toml`, changed when the user asks, alters how the
reports look. To change a shared page, edit the report sources, share again, and republish
to the same artifact. If a destination can take neither the folder nor the
single page, say so and ask the user before producing anything different.

### Remote runs and the hub

When experiments run elsewhere (a cluster, a cloud machine) or the user wants
all projects in one place, push them to a `cairn-report` hub: one
token-protected artifact store, run by the user. It keeps every version of each
project's report (sources and built pages, served at `<hub>/p/<project>/`, an
older version at `<hub>/p/<project>@<n>/`) and its runs, file by file, at
`<hub>/runs/<project>/`. Only set this up when the user provides a hub URL or
asks for one; never invent a hub or send project data to a server the user did
not name.

Configure the project without the token:

```toml
# cairn-report.toml
[hub]
url = "https://<hub-host>"
project = "<project-slug>"
token_file = "~/.config/cairn-report/hub-token"   # or CAIRN_HUB_TOKEN
exclude = [".submitit/**/*.pkl"]   # gitignore-style; Slurm job pickles stay local
```

Never write the token into the repository, configs, scripts, logs, or the
handoff; the config refuses a `token` key. Run remote jobs through the push
wrapper so their runs leave the machine while the job runs and once more when it
ends or is cancelled:

```bash
pixi run cairn-report push runs --watch -- python experiments/run.py experiment=<name>
```

Push only runs from a remote machine (`push runs`): reports are built locally,
and a report push from there would record a version without its pages. Where
the compute nodes themselves can reach the hub, `[logger] backends = ["hub"]`
lets the logger send each run's files while it executes instead; otherwise keep
the watcher.

On a cluster, `pixi run <cluster> submit` and `pixi run <cluster> pack` do this
automatically on the login node whenever `cairn-report.toml` has a `[hub]`, and
`finalize` sends a finalized study. The token must then exist on the cluster as
`CAIRN_HUB_TOKEN` or as the configured chmod-600 `token_file`, put there by the
user. A hub served on a login node at `127.0.0.1` is reachable only from that
node, so pin the target to it (for example
`KUMA_HOST=cdoering@kuma1.hpc.epfl.ch`, or `LYRA_HOST=...` for Lyra).

Locally, build the reports before pushing them (`pixi run report-build`, then
`pixi run cairn-report push`, which sends a new report version when anything
changed, plus new run files); the hub serves built output and never builds.
Pushes are incremental and verified, and the hub keeps every version, so push
freely. When the runs exist only on the hub, reports read them from there
(`run:` references and `run_dir()` download them into `generated/hub-runs/`),
as long as `[logger] backends` includes `"hub"`. `pixi run cairn-report pull`
brings the latest report back into `reports/` (it refuses to overwrite local
changes without `--force`), `pull --runs` the runs, and
`pull --name <project> --into <dir>` restores a project into a folder. In the
handoff, give the hub URLs of the reports and runs (`<hub>/p/<project>/`,
`<hub>/runs/<project>/`) next to the local ones. Comments made on the hub stay
in that browser; the user passes them on with the page's Copy button, like any
other comments.
