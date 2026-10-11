---
name: standalone-research-project
description:
  Initialize, extend, or develop a self-contained reproducible research project
  managed with pixi, Hydra-configured object construction, Hydra run outputs,
  and an interactive commentable report. Use when research must avoid MLflow,
  Cairn, Weights & Biases, or another experiment-tracking service while retaining
  reproducible experiments, analytical diagnostics, cumulative findings, and
  structured user feedback.
---

# Standalone Research Project

Build research projects that need no tracking service. Hydra's built-in output
directories are the sole experiment record. A locally hosted interactive report
reads those runs, presents the evolving evidence, accepts user comments, and
turns confirmed feedback into durable project knowledge.

## Core principles

1. **pixi owns the environment.** Prefer `[pypi-dependencies]` for Python
   packages; reserve conda-forge for the interpreter, compilers, CUDA, and
   packages PyPI does not provide reliably. Commit `pixi.lock`.
2. **Hydra owns configuration, object construction, and run outputs.** Put
   configs under `configs/`, construct configurable objects with `_target_` and
   `hydra.utils.instantiate`, and keep every run self-contained in Hydra's output
   tree. Do not add an experiment-tracking database or service.
3. **The experiment is the executable boundary.** A config-selected
   `Experiment` is the highest-level behavior. The entry point composes config,
   prepares the Hydra run directory, instantiates the experiment, and invokes it.
4. **The report is the research interface.** It is generated from Hydra run
   data, records current findings and uncertainty, and provides persistent,
   contextual commenting. It must never become an independent source of
   experimental numbers.
5. **Develop the method with the user.** Resolve consequential ambiguities,
   visualize intermediate behavior, and establish feasibility against relevant
   baselines before tuning or scaling.
6. **Validation tests the claim.** Identify smoke tests and debugging proxies as
   such; do not present them as scientific evidence.
7. **Do not improve results by weakening the problem.** Configure and disclose
   approximations that may change the scientific meaning.

## Project layout

```text
project/
├── pixi.toml
├── pixi.lock
├── .envrc
├── .gitignore
├── configs/
├── <concept>/
├── experiments/
├── outputs/
│   └── <run-name>/
│       ├── <timestamp>/        # completed Hydra run or multirun study
│       └── latest -> <timestamp>/
└── reports/
    ├── build.py                # reads runs and builds the report
    ├── serve_reports.py        # hosts the catalog and every report
    ├── serve.py                # legacy single-report preview
    ├── report.md               # authored narrative and executable snippets
    ├── generated/              # generated report, git-ignored
    └── knowledge/
        ├── comments.jsonl      # append-only user feedback
        └── findings.yaml       # reviewed cumulative knowledge
    └── <report-slug>/          # optional additional self-contained report
        ├── build.py
        ├── report.json
        ├── report.md
        ├── generated/
        └── knowledge/
```

Use a flat import layout rather than `src/<package>/`. Create concept directories
only when the project needs them. Before using a top-level name, check it with
`python -c "import <name>"`; if that succeeds, choose another name.

Hydra run outputs and generated report files are reproducible local data and are
normally git-ignored. Commit the report source and, unless the project contains
sensitive material, the compact knowledge files. If comments cannot be
committed, document their backup and transfer path explicitly.

## pixi setup

Start with:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project>"
platforms = ["linux-64"]

[dependencies]
python = "3.12.*"

[pypi-dependencies]
numpy = "*"
matplotlib = "*"
hydra-core = "*"
markdown-it-py = "*"
mdit-py-plugins = "*"
latex2mathml = "*"
plotly = "*"
black = "*"

[activation.env]
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
report-build = "python reports/build.py"
report-serve = "python reports/serve_reports.py --host 127.0.0.1 --port 8000"
report-host = "python reports/serve_reports.py --host 0.0.0.0 --port 8000"
format = "black --extend-exclude '/([.]pixi|outputs)/|/reports/(?:[^/]+/)?generated/' ."
```

Add the smallest suitable web dependency only when implementing the report
server. Keep building, local preview, and remote hosting available through the
three report pixi tasks. The server should build the report on startup when the
generated version is absent or stale, or clearly instruct the user to run
`pixi run report-build` first. Commit `pixi.lock`; ignore `.pixi/`, caches,
`reports/generated/`, and the appropriate `outputs/` data. Do not add MLflow,
Cairn, W&B, TensorBoard-as-a-tracker, or a custom run database.

Black normally honors `.gitignore` during recursive discovery, but `.pixi` is
not a built-in Black exclusion and an absent or overridden ignore rule can make
`black .` traverse the managed environment. Keep `.pixi/`, `outputs/`, the main
`reports/generated/`, and generated directories of additional reports in the
root `.gitignore`. Also retain the explicit `--extend-exclude` in the pixi task;
use `extend-exclude`, not `exclude`, so Black's defaults and `.gitignore`
behavior remain active. Formatter, linter, type-checker, and test discovery
configuration must all exclude environment directories and generated research
artifacts rather than scanning or modifying them.

## Hydra configuration and run identity

Put every scientifically meaningful choice in config. Let Hydra create distinct
run directories:

```yaml
# configs/config.yaml
defaults:
  - experiment: primary
  - _self_

seed: 0
run:
  name: <short semantic purpose>
  description: <question, purpose, and interpretation constraints>

hydra:
  callbacks:
    source_snapshot:
      _target_: provenance.source_snapshot.SourceSnapshotCallback
      mode: git                 # git or tree
      source_root: null         # Hydra's original working directory
      capture_runtime: true
  run:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
  sweep:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
    subdir: ${hydra.job.num}
  job:
    chdir: true
```

Hydra's `.hydra/config.yaml`, `.hydra/hydra.yaml`, and
`.hydra/overrides.yaml` are the authoritative configuration record. Add a small
machine-readable `run.json` only for facts Hydra does not already capture, such
as status, start and end times, code revision, actual device, or parent/source
run paths. Do not duplicate the full resolved config into another schema.

Names must be short and semantic—such as `feasibility-method`,
`reference-baseline`, or `ablation-no-feature`. Do not encode parameter lists,
seeds, timestamps, or hashes in them. Validate names as safe path slugs: reject
path separators, `.`/`..`, and characters outside the project's documented slug
alphabet. Put a concise description in config so a report reader understands
what was tested and how to interpret it.

### Snapshot source and runtime state

Copy [`assets/source_snapshot.py`](assets/source_snapshot.py) into the project as
`provenance/source_snapshot.py` and register it as shown above. Each Hydra job,
including every numbered multirun trial, writes `provenance/` into its own run
directory. The callback supports two modes:

- `git` stores a source-only archive of the committed tree at `HEAD`, a patch
  containing staged and unstaged changes, and eligible untracked source files.
  Prefer this compact mode when the project has a commit.
- `tree` copies the current eligible source tree as ordinary files. Use it when
  Git history is unavailable or the assembled working tree is more useful.

Both modes allowlist UTF-8 text source and project-definition formats. They
respect Git ignores when available and exclude symlinks, installed libraries,
environments, caches, dependency trees, generated reports, run outputs, binary
files, oversized files, and common credential filenames. Keep the per-file and
total-size bounds, and extend the deny rules for project-specific data or
secrets. A limit violation must fail the job rather than silently leave a
partial snapshot.

With `capture_runtime: true`, `provenance/environment/` also contains
`pip-freeze.txt`, Python and platform facts, a small allowlist of execution
environment settings, Git status, and an exact copy of `pixi.lock` when present.
Do not dump the complete process environment or copy `.pixi`; inventories and
the lock file describe installed packages without duplicating libraries or
exposing unrelated secrets. The callback runs before experiment code, so a
later experimental failure still retains its initial source and runtime state.

### Maintain a per-name `latest` link

After a single run completes successfully, atomically update
`outputs/<run-name>/latest` to a **relative symlink** targeting that run's
timestamp directory. A failed or interrupted run must remain available for
diagnosis but must not advance `latest`.

For a Hydra multirun, the timestamp directory is the study root and its numbered
subdirectories are trials. Only the sweep launcher updates `latest`, and only
after the whole study reaches the project's declared successful completion
condition; individual trials must never race to update it.

Implement this in one small project helper called by the entry point or an
appropriate Hydra callback. Create a sibling temporary symlink, then replace
`latest` atomically. Resolve and verify both the run-name directory and target
before replacement; never recursively delete or follow an existing link. If an
unexpected non-symlink already occupies `latest`, stop and report the conflict
instead of overwriting it.

Treat `latest` as a convenience pointer, never as provenance. Reports and
manifests must resolve it once and record the immutable timestamp-directory path
they actually read. When discovering runs, skip the `latest` directory entry so
the same run is not counted twice.

## Experiment boundary and run outputs

```python
# experiments/base.py
from abc import ABC, abstractmethod
from pathlib import Path


class Experiment(ABC):
    @abstractmethod
    def run(self, output_dir: Path) -> None:
        """Execute the experiment and write its evidence to output_dir."""
```

The Hydra entry point obtains the current run directory through
`HydraConfig.get().runtime.output_dir`, verifies the configured object implements
`Experiment`, and passes that path explicitly. The entry point must not know
experiment-specific orchestration.

Each run directory should contain only evidence useful for understanding or
reproducing that run. Use clear formats that report code can read without
project-specific reverse engineering:

- scalar summaries and metadata as JSON or YAML;
- evolving metrics as a tidy CSV, JSONL, or another documented open format;
- tables as CSV or Parquet when the dependency is already justified;
- Matplotlib figures as PNG or SVG, with source arrays retained when useful;
- images, grids, animations, models, and other rich outputs as ordinary files;
- logs for diagnosis, while keeping scientific values in structured files.

There is no universal result schema. Preserve stable names, units, columns, and
meaning when compatible experiments should share report views. Never hide
important evidence through final-only output, excessive aggregation,
cherry-picked examples, or presentation-only composites. Avoid redundant files
that make the result harder to interpret.

Write important outputs atomically where practical. A failed run must remain
recognizably incomplete and must not be selected as valid evidence merely
because its directory exists.

## Developing a method

### Establish shared understanding

Ask focused questions about ambiguities in purpose, inputs, outputs, operations,
state, update rules, objectives, invariants, assumptions, intended advantages,
and failure cases. Restate the current interpretation with equations,
pseudocode, diagrams, or simple examples and ask the user to confirm it. Record
confirmed choices in config, code, and the running report. Reopen the discussion
when implementation exposes a consequential ambiguity.

### Make behavior inspectable

Create simple examples that expose important mechanisms. Visualize inputs,
intermediate states, transformations, outputs, loss terms, update directions,
small optimization trajectories, baseline comparisons, ablations, spatial or
frequency views, and representative failure cases as appropriate. Create enough
complementary views for the user to verify the implementation, not decorative
figures merely to increase their number.

Prefer image grids for related inputs, references, predictions, residuals,
masks, samples, or steps. Keep layout, normalization, labels, and ordering
consistent when comparison matters, while retaining important full-resolution
outputs.

### Build diagnostics with Matplotlib

Implement reusable functions that accept explicit data and return a Matplotlib
`Figure`. Depending on the method, show objective terms, residuals, update
magnitudes, distributions, spatial maps, spectra, convergence, intermediate
states, uncertainty, before/after views, and baseline overlays. Give axes units
and meaningful labels; use legends and colorbars where needed. Keep scales,
limits, normalization, colormaps, and panel order consistent across comparable
figures. Save the figures into their Hydra run and reuse the same functions in
the report.

### Establish baselines and feasibility

Agree with the user which baselines test the claimed advantage. Prefer faithful
adaptations of authoritative reference implementations: read the paper,
documentation, configuration, evaluation protocol, and complete relevant
execution path. Record the reference version and material deviations.

Begin with a bounded feasibility study. Establish that the implementation
behaves as agreed on simple and representative cases, then compare it with the
chosen baselines. Agree on the qualitative checks, metrics, tolerances, and
failure cases needed to pass. Do not start systematic tuning, large Hydra
multiruns, or expensive scaling until the user has seen the evidence and the
method has passed this gate.

## Interactive running report

Create the report at the beginning of the project and maintain it throughout.
It must show the current method, questions, decisions, findings, supporting and
contradictory evidence, limitations, unresolved issues, and proposed next
experiments. Update conclusions when evidence changes while preserving enough
decision history to explain the current understanding.

### Keep the report editorially coherent

The report is the primary communication surface between the user and agent, not
an append-only activity log. Optimize it for a reader who needs to understand
the current method, evidence, and decisions quickly. Keep the main narrative
concise, use progressive disclosure for supporting detail, and remove
repetition, stale explanations, superseded conclusions, and figures that no
longer help answer an active question. Preserve provenance and decision history
in the manifest, run outputs, findings, and comment log rather than forcing all
history into the visible narrative.

When the user requests an edit, clarification, new comparison, or additional
evidence, first decide what that request means for the report's information
architecture. Integrate a local clarification where its concept is already
introduced; revise or replace the existing explanation instead of appending a
near-duplicate. If the request changes the method, interpretation, or research
question fundamentally, reconsider the section order, framing, summaries,
figures, and possibly the report boundary before editing. Split into another
report only when it serves a distinct audience or research question, not merely
because the current report became long.

After substantive updates, read the report as a whole. Check that its summary
matches its evidence, terminology is consistent, each section has a clear role,
and the most important open questions remain prominent. Condense or restructure
when additions obscure the argument. Do not respond to comments by mechanically
adding paragraphs at their location when the clearer resolution belongs
elsewhere in the report.

### Use callouts for synchronization

Use a callout when the user could otherwise miss information that materially
affects shared understanding or the next decision: an unresolved assumption, a
surprising limitation, contradictory evidence, a risk of misinterpretation, a
decision gate, or a focused question that needs the user's judgment. Callouts
are attention signals, not general formatting. Keep each one short and
actionable, give it a specific title, and state why it matters or what response
is needed. Remove or rewrite it after the issue is resolved; do not accumulate
stale callouts or use them for ordinary findings already clear in the text.

The canonical Markdown renderer supports admonition blocks. Prefer `question`
for requested user input, `decision` for a pending or confirmed choice,
`warning` or `risk` for consequential limitations, and `important` for context
the reader must not overlook:

```markdown
!!! question "Which reference behavior is authoritative?"
    The two candidate baselines use different boundary handling. Confirm the
    intended behavior before feasibility results are interpreted.
```

Callouts remain selectable and commentable, retain their Markdown source-line
anchors, and use the shared report style. Do not hide essential evidence only
inside a collapsible callout.

### Use the canonical report template

Start every standalone report from
[`assets/report-template`](assets/report-template), installed with:

```bash
python <skill-directory>/scripts/scaffold_report.py <project-root>
```

The scaffold includes the builder, comment-capable server, shared HTML/CSS/JS,
knowledge files, sample data, and three example diagnostic figures. Run
`reports/build.py` immediately after scaffolding: the sample report is both a
working smoke test and a visual reference for the required behavior. Replace
its example content with project evidence; do not redesign the report for each
project or fork its interaction model without a user requirement.

### Host multiple reports together

When a project has more than one report, keep the original report at
`reports/` and place each additional self-contained report at
`reports/<report-slug>/`. Create an additional report from the same canonical
template with:

```bash
python <skill-directory>/scripts/scaffold_report.py <project-root> --report <report-slug>
```

Use short, stable lowercase slugs. `serve_reports.py` discovers the main report
and direct child reports, builds all of them on startup, and exposes one catalog
at `/`. Individual reports live at `/reports/main/` and
`/reports/<report-slug>/`; their comment APIs and knowledge files remain
isolated. The catalog is defined by `template/reports-index.html`,
`reports-index.css`, and `reports-index.js`. It must derive cards from each
report's `report.json`, escape text through DOM APIs, use the shared visual
language, and show title, subtitle, status, and update information. Do not make
users remember separate ports or URLs for reports in the same project.

Treat the template's design tokens, typography, spacing, navigation, status
badges, finding cards, metric cards, figure cards, lightbox, floating comment
composer, and responsive breakpoints as the shared report style. Extend them
through the existing variables and components. Do not introduce one-off inline
styles or a second visual system in generated sections. Scope component
selectors to the report's own classes (for example `.figure-card .figure-copy`,
`button.icon`), never bare descendant tags or generic class names. Embedded
libraries such as Plotly use their own `div`s and `svg.icon` elements, and
leaking rules distort them.

Populate `reports/report.json` through deterministic report-building code. Its
top-level content comprises project metadata, summary metrics, findings,
figures, next experiments, and source runs. Each finding and figure needs a
stable ID so links and comments survive rebuilds. Escape all textual content by
creating DOM text nodes; never interpolate untrusted content as HTML.

Every displayed image or Matplotlib figure must be a clickable figure card and
participate in one ordered lightbox gallery. When enlarged, users must be able
to move to the previous or next figure with visible controls and the left/right
arrow keys, close with Escape, and zoom with visible controls, `+`/`-`, or the
mouse wheel. Wheel and keyboard zoom are anchored at the hovered point, so the
pixel under the cursor stays fixed; the visible zoom buttons zoom about the view
center. A zoomed image must support mouse and touch panning so users can
inspect every region, and resetting or changing figures resets both zoom and
pan. Disable the browser's native image drag (`draggable="false"` and
preventing `dragstart`); otherwise it cancels the pointer stream mid-pan. Card previews must show the complete image using `object-fit: contain` or
an equivalent intrinsic-aspect-ratio layout; never crop analytical content to
normalize card shapes, and keep captions in a separate region. Preserve
meaningful alt text, captions, keyboard focus, stable
ordering, and full-resolution sources. Test these behaviors at desktop and
mobile widths whenever the template or generated markup changes.

Support Plotly figures as first-class interactive diagnostics. Write each
figure as a Plotly JSON artifact containing `data`, `layout`, and optional
`config`, then reference it from `report.json` with `type: "plotly"`, a stable
ID, and its artifact path. Bundle the installed Plotly.js runtime into the
generated report at build time; never depend on a CDN. Render Plotly cards
interactively with hover only: hide the mode bar and disable scroll zoom in the
card preview so controls never cover the figure and page scrolling is not
captured. Provide an icon-only full-screen control. In the lightbox,
retain Plotly's native hover, zoom, pan, selection, reset, and image-export
tools, while keeping the report's previous/next navigation and icon-only
commenting. Static images and Plotly figures share one ordered gallery.

### Executable Markdown

Support LaTeX-style mathematics directly in the Markdown narrative. Use
`$...$` for inline mathematics and `$$...$$` on separate lines for display
equations. Parse math with `mdit-py-plugins` and convert it during the build to
semantic MathML with `latex2mathml`; do not require a third-party CDN at report
viewing time. Preserve equation source-line anchors, allow equation labels, and
make wide display equations horizontally scrollable without clipping the page.
Post-process the MathML so delimiters outside `\left`/`\right` are
`stretchy="false"`. `latex2mathml` emits `\lVert`, `\lvert` and similar as bare
`<mo>` elements, which browsers stretch as fences, so the two sides of a norm
render at different heights. Wrap each formula with its LaTeX source in
`data-latex`. A selection inside a formula then quotes `$<latex>$` (rendered
MathML text is unusable as a quote), anchors to the equation's source line, and
highlights the whole formula.
Treat unsupported LaTeX as a build error so broken notation is never silently
published. Use ordinary fenced code when dollar signs are intended literally.

Write the narrative in `reports/report.md`. Ordinary fenced code is display-only.
Execute a block only when its fence is explicitly marked `python exec`; add
`hide` to execute without displaying its source:

````markdown
```python exec hide
from pathlib import Path
import matplotlib.pyplot as plt

values = load_values(PROJECT_ROOT / "outputs" / "method" / "latest")
plt.plot(values)
```
````

Executable blocks share one namespace in document order, capture stdout, and
embed newly created Matplotlib figures directly in the generated HTML. The
builder exposes `REPORT_ROOT` and `PROJECT_ROOT`; blocks must load experimental
values from Hydra output files rather than paste copies into Markdown. A block
exception must fail the entire build. Keep execution opt-in: never execute an
unmarked fence or code derived from a report comment.

The canonical builder is intentionally local and trusted; executable Markdown
has the report author's permissions. Do not build untrusted Markdown. For slow
reports, add content-addressed caching keyed by the source block, dependencies,
and input-file digests. For potentially unbounded or third-party code, execute
through a subprocess with a declared timeout and resource policy rather than
weakening failure behavior.

### Reproducible evidence

The report builder discovers valid Hydra run directories and reads their
`.hydra/` configs and structured outputs. It must record a machine-readable
manifest alongside every build containing the selected run paths, file hashes
or mtimes, selection criteria, report revision, and code revision. Every metric,
table, image, figure, and claim displayed from an experiment must link back to
its source run and, where feasible, source file. Never manually copy results
into report code or findings files.

Rebuilding from the same checkout, knowledge files, and preserved Hydra outputs
must reproduce the report. When run data is too large to retain locally, require
a documented external data location and integrity digest; do not silently make
the report irreproducible.

### Persistent contextual comments

Serve the report through a small project-owned web application. All report
content must be commentable by selecting its text, including the overview,
metrics, findings, tables, figure captions, run references, narrative, and next
steps. Since image pixels cannot be selected, place a small icon-only speech
bubble on every image card and in the lightbox; it creates a comment anchored
to the stable figure ID or Markdown source line. Do not add text-labeled or
section-level `Comment` buttons. Give every generated content
region a stable target; the builder additionally attaches source-line metadata
to rendered Markdown blocks. Selection comments record both the target and
selected quote, plus the source line when available. Consumers locate the quote
first because line numbers drift after edits.

Keep comment entry deliberately lightweight. Selecting report text reveals only
a small speech-bubble icon beside the selection, never a text-labeled button;
clicking that icon or an existing comment bubble opens a small floating textarea
beside that context, not a modal dialog. Show only a short
context label or quote and the textarea. Do not ask for an author, title,
category, or other metadata, and do not require a Save button. Autosave after a
short typing debounce, show a subtle saving/saved state, and dismiss on Escape
or an outside click without interrupting report navigation.

In hosted mode, store comments server-side in
`reports/knowledge/comments.jsonl`. Show each current comment where it applies:
softly highlight the quoted text with a small inline speech bubble at its end,
or highlight the target region when there is no quote. Clicking the highlight
or bubble reopens the comment for editing. Each figure holds a single comment:
its speech-bubble icon (on the card and in the lightbox) switches to a filled
state, the card gets a subtle highlight, and every entry point reopens that
comment instead of creating another bubble. If a quote can no longer be found,
show a visibly stale bubble on the nearest surviving target.
Each append-only record includes a stable ID, timestamp, stable target, Markdown
source line when applicable, selected quote, comment text, and optional reply-to
ID. Autosaved edits append revisions under the same ID; the API and report fold
those revisions to the latest state without erasing their history.
Preserve comments across rebuilds and show clearly when their target is obsolete.

The rail holds two side-by-side icon-only buttons with styled tooltips (not
text labels): **Copy comments** and **Clear all comments**. Copy puts a
ready-to-paste prompt on the clipboard: brief handling instructions followed by
every open comment (hosted and browser-only) as JSON. Clear opens a small
in-page confirmation popover (never a browser `confirm()` dialog) that states
the count. Confirming calls `POST /api/comments/clear`, which appends a
`resolve` event with the resolution "Cleared from the report" for every open
comment, and it discards browser-only drafts. The history is never erased.
Both buttons report their outcome briefly in their tooltip. Use the async clipboard
API, falling back to a hidden-textarea copy on non-secure origins such as a
plain-HTTP remote host. If the persistence endpoint is unavailable, retain new
comments in browser storage; they are marked `"storage": "browser"` in the copied
payload. Keep `/api/comments/export` for programmatic retrieval. Copied or
exported comments retain the same schema, and the agent must reconcile them into
the append-only knowledge store without silently duplicating records.

The Markdown author may also leave invisible source comments such as
`<!-- @agent: compare this claim with the reference run -->` (and legacy
`@claude` comments). Before a report is considered reviewed, the agent must
address each directive, rebuild and validate the report, then remove the source
comment or replace it with an explicit documented resolution.

For every open exported or hosted comment, locate its selected quote first and
fall back to its source line or stable target only when necessary. Make the
requested change or ask when its consequence is ambiguous, rebuild the report,
and append a resolution event
`{"id": "<comment id>", "event": "resolve", "timestamp": "<ISO time>", "resolution": "<what changed>"}`
to `comments.jsonl`. The report then stops showing that comment as open. Never
rewrite or delete the original comment record.

Support resolution without deleting history: append a status event or retain
the original comment with resolution state and rationale. Treat comments as
user input, not automatically as scientific fact. The agent reviews new
comments, asks for clarification when their consequence is ambiguous, and
updates code, experiments, report interpretation, or planned work as warranted.

### Accumulating knowledge

Maintain `reports/knowledge/findings.yaml` as a concise reviewed synthesis, not
a second store of raw experimental data. Each finding should state the claim,
status (for example tentative, supported, contradicted, or superseded), source
run paths, relevant report anchors, originating comment IDs when applicable,
known limitations, and last review time. Claims remain traceable to Hydra run
files; comments explain user judgment and context.

When new results or comments conflict with a finding, surface the conflict in
the report and revise its status rather than silently overwriting it. The report
builder combines Hydra evidence, reviewed findings, and comments into the
current view. The agent should explicitly summarize what knowledge changed
after incorporating a feedback round.

### Hosting and safety

Always provide exact local-preview and remote-hosting commands with their
concrete URLs. The example tasks use:

```bash
pixi run report-build
pixi run report-serve  # http://127.0.0.1:8000
pixi run report-host   # http://<remote-host>:8000
```

Replace `<remote-host>` with the actual hostname or reachable IP in the
handoff. `report-serve` is the safe local default; `report-host` binds to all
interfaces. Because the report accepts writes, do not expose it directly to an
untrusted network. Use a trusted private network, VPN, or authenticated HTTPS
reverse proxy. The server must validate comment size and format, escape
untrusted text when rendering it, and restrict writes to the intended knowledge
files.

## Parameter studies

Only after feasibility, use Hydra multirun for repeated comparable trials.
Declare the parameter space, seed, budget, objective, and direction. The report
must identify all trial directories, their status, and the selected result. Use
a finite grid for intentional comparisons, random search for bounded
exploration, and an appropriate Hydra sweeper plugin only when adaptive search
is justified. Do not add a tracking service merely to run a sweep.

## Perceptual blind spots

When the user reports an important effect that current inspection or metrics
miss—such as temporal instability, localized artifacts, or high-frequency
structure—preserve the original outputs, add an analytical visualization that
isolates the phenomenon, and record a plausible quantitative measure.

Prefer a standard established metric when its assumptions fit. Adapt or devise
a specific measure only when standard metrics are unavailable or miss the
effect. When its relation to perception is unclear, test known positive,
negative, and confounding cases. If uncertainty remains, propose a small
calibration phase using focused ratings, rankings, or pairwise comparisons.
Record the resulting interpretation and limitations in the report.

## Documentation and handoff

The handoff states what changed or was learned, what validation supports it,
and what could still limit the conclusion. Distinguish smoke tests and proxies
from evidence. Include exact commands for reproducing experiments, rebuilding
the report, and hosting its commentable interface; provide the concrete URL and
explain where comments and reviewed findings are stored.

## Reproducibility checklist

- [ ] `pixi.lock` is committed and a fresh clone can run documented pixi tasks.
- [ ] `.pixi`, Hydra outputs, and generated report trees are ignored and
      explicitly excluded from recursive formatting and other source tooling.
- [ ] No external or custom experiment-tracking service or database is used.
- [ ] Every run retains Hydra's `.hydra/` configs plus structured results and a
      recognizable completion state in its Hydra output directory.
- [ ] Every run contains bounded `provenance/` data in `git` or `tree` mode,
      plus `pip freeze`, runtime facts, Git status, and `pixi.lock` when present;
      environments, installed libraries, outputs, binaries, and secrets are not
      copied as source.
- [ ] Runs use `outputs/<run-name>/<timestamp>/`; after successful completion,
      `outputs/<run-name>/latest` atomically points to that immutable directory.
- [ ] Failed runs do not advance `latest`; multirun trials do not race to update
      it; report manifests record resolved timestamp paths rather than symlinks.
- [ ] Run names are concise and semantic; descriptions explain their purpose.
- [ ] Reusable Matplotlib diagnostics expose intermediate behavior, and related
      images use consistent grids where practical.
- [ ] The user confirmed the method specification and consequential ambiguities.
- [ ] Relevant baselines are faithful and a bounded feasibility study precedes
      tuning or large multiruns.
- [ ] The running report is generated from Hydra run outputs and every displayed
      result links to a source run or file.
- [ ] The report remains concise and structurally coherent: new requests are
      integrated or used to restructure existing material rather than appended
      mechanically, and the visible narrative contains no stale duplication.
- [ ] Callouts highlight only consequential synchronization needs, state the
      required decision or response, and are removed or revised when resolved.
- [ ] The canonical report template and builder are used; shared design tokens
      and components keep styling consistent across projects and rebuilds.
- [ ] When multiple reports exist, the shared host discovers and builds all of
      them, lists them at `/`, and keeps routes, hosted comments, and browser
      fallback comments isolated by stable report slug.
- [ ] Every image opens in the ordered lightbox; previous/next controls, arrow
      keys, Escape, zoom buttons, cursor-anchored `+`/`-` and wheel zoom, and
      pointer/touch panning work as documented, while card previews never crop image content.
- [ ] Plotly JSON artifacts render interactively from a locally bundled runtime,
      show a clean hover-only card preview, retain native zoom/pan/hover tools in
      the lightbox, and participate in the same gallery
      and comment system as static figures.
- [ ] Only `python exec` Markdown fences execute; failures fail the build,
      stdout and figures are embedded, and experimental data comes from files.
- [ ] Inline and display equations build to semantic MathML, retain source
      anchors, keep bare delimiters non-stretchy, quote their LaTeX source when
      commented, and remain readable without a browser-side CDN.
- [ ] Every report build has a source manifest sufficient to reproduce it.
- [ ] Comments persist server-side with stable targets and immutable history;
      resolving a comment does not erase it.
- [ ] Text selection throughout the report creates comments with stable targets;
      Markdown selections also retain source lines, and Copy comments plus
      hosted persistence work without losing comments. Clear asks for in-page
      confirmation and only appends resolve events.
- [ ] Every image and lightbox view has an icon-only comment affordance anchored
      to the figure ID or Markdown source line.
- [ ] Comments autosave without a Save button; highlighted regions and their
      bubbles reopen them for editing, and each figure holds one comment.
- [ ] Reviewed findings cite source runs and comment IDs, expose conflicts, and
      distinguish evidence from user interpretation.
- [ ] User-reported blind spots receive analytical views and suitable metrics;
      established measures are preferred and calibrated only when needed.
- [ ] The report server safely handles untrusted comment text and is not exposed
      unauthenticated to an untrusted network.
- [ ] The handoff includes exact report build, local-preview, and remote-hosting
      pixi commands, concrete URLs, and the locations of run data, comments,
      and findings.
