# Reports

Read this before creating, writing, or answering in reports, and before handling
sent comments. How to write a direction's method is in
[writing-methods.md](writing-methods.md).

Contents: what a report is; whose report it is; agent blocks; agent reports;
syntax; numbers and figures; comments; viewing.

## What a report is

A report is a document in the project's Cairn repository, not a file in the
project. The user edits it in the browser as they read it; agents read and write
the same document as Markdown through `cairn report`. A report runs no code:
analyses are runs that log their tables and figures, and the report embeds them.
There is no build, publish, or export step. Every saved text of a part is kept as
a revision, and a write against an older revision is refused instead of
overwriting.

```bash
pixi run cairn report list
pixi run cairn report show NAME                 # every part; the body also as markdown
pixi run cairn report write NAME body body.md --revision N --by agent
pixi run cairn report write NAME SLOT answer.md --revision N --by agent
pixi run cairn report new NAME body.md --owner agent --origin ORIGIN --slot SLOT
```

Always pass `--revision` with the revision of the part you read (`report show`
lists it; a part not written yet is at 0). Without it, a write silently replaces
whatever the user saved in between. On a conflict, read the part again, merge,
and write again. Names are short, lowercase, and may nest with `/`
(`study/grids`). Link to
another report as `[grids](/p/PROJECT/r/study/grids)`.

## Whose report it is

Every report has an owner, `user` or `agent`, and the owner writes its body.

- **The user's report** is the user's: their plan, their framing, their
  sections. Write only into its agent blocks. Change the body only when the user
  asks, and then only what they asked: do not add an Abstract, Background,
  related work, or any other section, restructure, or "clean up" text they did
  not mention. Read the current revision first and write with `--revision`.
- **An agent report** is yours to write. The user steers it with comments, and
  **Take over** in the UI makes it theirs; from then on it is the user's report
  and the rule above applies. `report show` tells you the owner; check it before
  every write.

## Agent blocks

The user types `@agent` on a line of its own where an agent should work. In
Markdown, a block is `<?cairn agent SLOT?>`. Its conversation is the block's
comments without a quote; the first sent message is the request, and later
messages refine it. A template's block may carry a suggested request
(`<?cairn agent SLOT "..."?>`); it is a request only once the user sends it.

Answer in the block itself:

```bash
pixi run cairn report write NAME SLOT answer.md --revision N --by agent
pixi run cairn comments reply c_ROOT "Done: the baseline converged; see the block" --by agent
```

The answer is what the user asked for and nothing more: the result, with the
embedded tables and figures that show it, and one or two sentences on what it
means and what is still open. Rewrite the answer when the work moves on instead
of appending to it. When the request asks to explore, the answer is short and
the work goes into agent reports under the block (below).

## Agent reports

Create an agent report for each direction you explore, under the block that
asked for it, named after the direction:

```bash
pixi run cairn report new study/grids grids.md --owner agent --origin study --slot directions
```

The UI shows it as a card under that block and in the report tree. Agent
reports may start further agent reports under their own blocks. When the user
asks for a report in chat rather than in a block, create a standalone agent
report (`--owner agent`, no origin) and give them its URL.

Every agent report opens with the same header, so the user can scan many:

```markdown
**Claim.** Multi-resolution grids match the baseline's error with far fewer parameters.
**Setup where it holds.** 2D signed distance fields of the thin-shell set at 256²; not tested in 3D.
**Status.** supported
**Evidence.** The error table and the error maps below, from runs/grids-eval.
```

- **Claim**: one sentence, qualitative, no result number.
- **Setup where it holds**: the data, scale, and budget the claim was tested on,
  and what was not tested.
- **Status**: `proposed` (nothing run yet), `running`, `supported`,
  `contradicted`, `inconclusive`, or `abandoned`, with the reason for the last
  three in a few words.
- **Evidence**: which runs and which embeds below carry the claim.

Below the header, use the structure the question needs. A research direction
follows the paper-like spine in [writing-methods.md](writing-methods.md); an
inspection, validation, or comparison uses only the sections its question needs.
Write it before the evidence: the claim to test, the setup, and the method,
with `proposed` status; fill in the evidence as runs complete and revise the
header with it.

Keep each report coherent for a reader who needs the current state quickly:
integrate changes where they belong, remove what is stale, and re-read the
whole report after substantive changes. It is not an activity log; the revision
history keeps the past.

## Syntax

Reports are Markdown: headings, lists, tables, `$...$` and `$$...$$` math,
code fences (shown, never run), and callouts:

```markdown
::: {.callout-warning}
**Question: which boundary handling is authoritative?** The two baselines differ;
confirm before the results are interpreted.
:::
```

Callout kinds are `note`, `tip`, `warning`, and `important`. Use one when the
reader could otherwise miss something that changes the next decision (an
unresolved assumption, a surprising limitation, contradicting evidence,
overlapping prior art, a question for the user), say what response is needed,
and remove it once resolved.

Artifacts appear through `cairn:` references, each on a line of its own:

```markdown
![Error on the test set](cairn:runs/grids-eval@latest#figures/error.png)
![](cairn:runs/grids-eval@latest#results)
![](cairn:runs/grids-eval@v3)
```

`REF#name` shows the file or typed value the run added under that name: images,
SVG, video, and audio play, Plotly figures stay interactive, and tables show as
tables. `REF` alone shows the run's value. `@latest` is fine: the report shows
the newest version, so after a rerun re-read every claim that rests on it. Use
an exact `@vN` only where the claim is about that version, for example when
comparing an old run with its fix.

A viewer (an artifact's `index.html` with its scripts beside it, for example a
three.js mesh viewer added by a run as `viewers/mesh`) shows with settings in a
`view` block; `viewer` and `caption` are reserved, every other key is passed to
the viewer, and `cairn:` strings become links to those files:

````markdown
```view
viewer: cairn:viewers/mesh@latest#index.html
caption: Lucy decimated to 250k and 50k triangles
meshes:
  - label: 250k triangles
    file: cairn:datasets/lucy@v2#lucy-250k.obj
```
````

The viewer reads its settings with
`JSON.parse(decodeURIComponent(location.hash.slice(1)))`, runs sandboxed, and
loads its own files by relative path.

## Numbers and figures come from runs

**Never type a result number into a report.** Every result enters as an embed
of what a run recorded: a table, a value, or a figure. Prose says what the
embedded result shows qualitatively ("lower on every setup, most at the
thinnest shells") and points at it. Design constants that define the setup (a
resolution, a threshold, a budget) may be typed.

So results need an analysis run: one per figure or table group, named after
what it shows, that `run.use`s the runs it reads and adds its tables and
figures under names the report embeds (`cairn.add(cairn.Table(rows),
name="results")`, `cairn.add(cairn.Figure(figure), name="figures/error")`;
`track` writes records over steps for the UI, not embeddable files). Changing a
figure means rerunning only it. Only completed, scientifically validated runs count as
evidence; a smoke test or proxy is labelled as such.

Which figures a method needs is in [writing-methods.md](writing-methods.md).
Make each one the way a paper figure is made, not with an automatic layout
engine (Graphviz, torchview, Mermaid). Choose the medium by what it shows:

- **Structure** (an architecture, an overview): a self-contained SVG written by
  hand and added by a run (an `illustrations` run with `run.add(path,
  name="figures/architecture.svg")`), embedded like any figure.
- **Geometry and setup** (a scene, camera and light placement, a sampling
  domain, the train/test split): drawn to scale by code from the run's resolved
  config, with matplotlib or a function that writes SVG, in an analysis run.
  Add schematic annotations (labelled angles, distances, the varied parameter
  and its range) on top.
- **Data** (the test inputs, a degradation, an intermediate state): the real
  images or renders from the project's code, as a labelled grid.

A good method or setup figure:

- has one reading direction and places components on a shared grid; geometry
  keeps its true proportions and shows axes or a scale;
- shows the few components the text names, at the depth a paper figure would;
- labels quantities with the symbols of the equations, in Unicode with italic
  variables, and tensor shapes only where they explain the method;
- encodes kinds of things consistently with one restrained palette, and a single
  accent colour for what this direction adds; the caption says so;
- has straight or orthogonal arrows that end at box edges, no crossings, text at
  least 11 px at report width, and no wasted margin.

**Look at it before you use it.** Render it to an image and open it
(`pixi exec --spec librsvg rsvg-convert -w 1600 figure.svg -o /tmp/figure.png`
for SVG), fix overlaps, clipping, misalignment, and stray arrows, and look again
in the report at its displayed width. For a neural network, compare the drawing
against `print(model)` and the shapes of one forward pass.

## Comments

**Always watch.** At the start of every session in a project with reports, start
one watcher in the background, in a way that wakes you when it exits (in Claude
Code, Bash with `run_in_background`; not the Monitor tool, which times out):

```bash
pixi run cairn comments watch 'reports/**' --json --once
```

It waits until a thread has a comment sent after its last reply, prints the
threads as one JSON line, and exits. Handle them, then start it again. Keep
exactly one watcher; check for one you started before starting another. Without
background processes, check `pixi run cairn comments list 'reports/**' --json`
at checkpoints and before ending each turn.

A thread can hold unsent drafts: act only on sent messages (`sent_at` set) and
use the rest as context. Its anchor says where it points: an agent block
(`path` is the slot), a passage (quote and lines), or a figure (`media_key`,
with a region or time). A comment on an agent block is a request or refinement
for that block. A comment on a passage or figure of an agent report is feedback
on your text; on the user's report, it asks for exactly what it says.

Do the work, then reply in the thread with the outcome, and resolve the root
only when everything it asked is done:

```bash
pixi run cairn comments reply c_ROOT "Added the 3D case; it does not hold there (see Status)" --by agent
pixi run cairn comments resolve c_ROOT --note "3D results in the block" --by agent
```

Leave blocked or ambiguous requests open and ask a focused question in a reply.
Comments are guidance, not scientific evidence.

## Viewing

Reports show in the Cairn UI of the selected repository: `pixi run ui` for a
local one, or the remote server's UI. Give the user the report's URL,
`<ui>/p/<project>/r/<name>`. The report list shows the user's reports and,
under them, the tree of agent reports.
