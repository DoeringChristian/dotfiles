# Reports

Read this before creating, writing, or changing a report, and whenever the user
gives you a reference to a place in one. How to write a direction's method is in
[writing-methods.md](writing-methods.md).

Contents: what a report is; how agents read and write; how the user tells you
what to change; whose report it is; agent reports; syntax; numbers and figures;
viewing.

## What a report is

A report is a Markdown file that the user and agents write at the same time. It
lives in **cairn-ui**, the program that shows the pages, and has nothing to do
with the runs' repository: Cairn itself knows no reports, and a report is not an
artifact. It runs no code: analyses are runs that log their tables and figures,
and the report shows them by reference. There is no build, publish, or export
step, and no history: only the current text exists.

The user edits in the browser. Every change you make appears there at once, and
the user may be typing while you write.

## How agents read and write

All commands ask a running cairn-ui. `ui` in `.cairn.toml` (or `CAIRN_UI`, or
`--url`) names it, and the project comes from `.cairn.toml` too; the token is
the one that the server uses.

```bash
pixi run cairn-ui report list
pixi run cairn-ui report show NAME > /tmp/report.md
pixi run cairn-ui report edit NAME --old "the passage" --new "what it becomes"
pixi run cairn-ui report write NAME --base /tmp/before.md --file /tmp/after.md
pixi run cairn-ui report write NAME --file new.md        # also creates it
pixi run cairn-ui report delete NAME                     # only when the user asks
```

- **Prefer `edit`** for any change to an existing report. It replaces the one
  passage that reads exactly `--old` and touches nothing else. It fails when the
  passage is not there exactly once: read the report again, and give a longer or
  current passage.
- **Rewriting more:** keep a copy of what you read (`show > before.md`), change
  a second copy, and `write --base before.md --file after.md`. What others wrote
  since you read it is merged in; where both changed the same lines, both stay,
  so read the result and resolve it.
- **Never `write` an existing report without `--base`.** It replaces the whole
  text, including what the user is typing.
- Read the report again right before you change it, and after. Use
  `--new ""` to remove a passage. Pass multi-line text as quoted arguments
  (`--new "$(cat passage.md)"`).

Names are short and lowercase, and may nest with `/` (`study/grids`). The files
lie beside cairn-ui's database; use the commands, not the files.

Workspaces (the pages of live curves) are cairn-ui's too:
`pixi run cairn-ui workspace list | show NAME | write NAME --file layout.json
--expected REVISION`. Change one only when asked.

## How the user tells you what to change

There are no comments, agent blocks, or watchers. The user asks in the chat,
often with a reference copied from the report, or writes a note to you in the
report's text and tells you to look.

A copied reference names the report, the line, and the exact Markdown:

```text
study/grids.md:12 "The loss **falls** quickly" [cairn:reports/study/grids]
```

- The quoted passage is what `edit --old` needs. The line number is where it was
  when it was copied: search for the passage, do not trust the line.
- A reference to a figure quotes its `![…](cairn:…)`; one from an enlarged
  image or video is JSON with the report (`file`), the run and path
  (`artifact_ref`), and a region (pixels) or time (seconds). Look at that region
  or time before you answer.
- Do exactly what is asked at that place, then say in the chat what you changed.
  When the request is a question, answer it in the chat; change the report only
  if it asks for that or the text is wrong, and say so.
- If the passage is gone or no longer fits the request, ask.

## Whose report it is

Cairn-ui does not record an owner. The rule is by how the report came to be:

- **The user's report** is every report the user started: their plan, their
  framing, their sections. Change only what they ask, where they ask it. Do not
  add an Abstract, Background, related work, or any other section, restructure,
  or "clean up" text they did not mention. Results they ask for go where they
  say; if they did not say, propose a place in the chat.
- **An agent report** is one you created and that opens with the header below.
  It is yours to write. The user may edit it: keep their changes, build on them,
  and never write over them. Once they tell you it is theirs, it is.

When you cannot tell, treat it as the user's.

## Agent reports

Create an agent report for each direction you explore, named below the report it
belongs to:

```bash
pixi run cairn-ui report write study/grids --file grids.md
```

Tell the user its name and URL in the chat. Link it from the user's report only
if they ask (`[grids](/p/PROJECT/r/study/grids)`).

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
- **Evidence**: which runs and which figures below carry the claim.

Below the header, use the structure the question needs. A research direction
follows the paper-like spine in [writing-methods.md](writing-methods.md); an
inspection, validation, or comparison uses only the sections its question needs.
Write it before the evidence: the claim to test, the setup, and the method,
with `proposed` status; fill in the evidence as runs complete and revise the
header with it.

Keep each report coherent for a reader who needs the current state quickly:
integrate changes where they belong, remove what is stale, and re-read the
whole report after substantive changes. It is not an activity log.

## Syntax

Reports are Markdown: headings, lists, tasks (`- [ ]`), tables, `$...$` and
`$$...$$` math, code fences (shown, never run), and callouts:

```markdown
> [!warning] Question: which boundary handling is authoritative?
> The two baselines differ; confirm before the results are interpreted.
```

Callout kinds are `note`, `tip`, `warning`, and `important`. Use one when the
reader could otherwise miss something that changes the next decision (an
unresolved assumption, a surprising limitation, contradicting evidence,
overlapping prior art, a question for the user), say what response is needed,
and remove it once resolved.

Keep an empty line around tables, figures, and blocks.

What a run holds appears through `cairn:` references, `REF#path`, where the path
is the key it was logged under (or a path inside it):

```markdown
![Error on the test set](cairn:runs/grids-eval@v3#figures/error)

![Ours](cairn:runs/ours@v1#render){width=50%} ![Reference](cairn:runs/reference@v1#render){width=50%}

The final error was ![error](cairn:runs/grids-eval@v3#rmse).
```

- Images, SVG, video, and audio play, Plotly figures stay interactive, tables
  show as tables. Several on one line stand beside each other; `{width=NN%}`
  sets a share of the line.
- A number or text shows as itself within a sentence. This is how a result
  number enters prose.
- `[the run](cairn:runs/grids-eval@v3)` links to the run.
- The selector is `@vN`, an alias, or `@latest` (the newest *completed* version,
  also without a selector). `@latest` moves: after a rerun, re-read every claim
  that rests on it. Use `@vN` where the claim is about that version.

A `card` block shows live curves, images, or figures of several runs, as a
workspace card does:

````markdown
```card
kind: scalar
runs: [runs/ours-*, runs/baseline-ai57_008@v2]
x: step
y: loss
logY: true
height: 360
caption: Training loss of every variant
```
````

`kind` is `scalar`, `image`, `video`, or `plotly`; `runs` are references, or names
with `*` (the newest completed version of each). Other keys are the card's
settings: `x`, `y`, `logX`, `logY`, `split` (a list, default `["@run"]`),
`value` and `axis` for media (the key and the step axis), `mode` (`gallery`,
`compare`, `sequence`), `columns`.

A `view` block loads a viewer, an artifact's `index.html` with its scripts beside
it. `viewer` and `caption` are reserved, every other key is passed to the viewer,
and `cairn:` strings become links to those files:

````markdown
```view
viewer: cairn:viewers/mesh@v1#index.html
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

**Never type a result number into a report.** Every result enters as a
reference to what a run recorded: a table, a value, or a figure. Prose says what
the shown result means qualitatively ("lower on every setup, most at the
thinnest shells") and points at it. Design constants that define the setup (a
resolution, a threshold, a budget) may be typed.

So results need an analysis run: one per figure or table group, named after
what it shows, that `run.use`s the runs it reads and logs its tables and figures
under the keys the report references:

```python
with cairn.run("error-maps-ai57_008-widths", config, {"description": "..."}) as run:
    source = run.use("runs/eval-ours-ai57_008-w64@v2", role="evaluation")
    rows = source["cases"].load()
    run.log({"results": cairn.Table(summary(rows)), "figures/error": cairn.Figure(error_figure(rows))})
```

Changing a figure means rerunning only it. Only completed, scientifically
validated runs count as evidence; a smoke test or proxy is labelled as such.

Which figures a method needs is in [writing-methods.md](writing-methods.md).
Make each one the way a paper figure is made, not with an automatic layout
engine (Graphviz, torchview, Mermaid). Choose the medium by what it shows:

- **Structure** (an architecture, an overview): a self-contained SVG written by
  hand and added by a run (an `illustrations` run with
  `run.add("architecture.svg", "figures/architecture.svg")`), shown like any figure.
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

## Viewing

Reports show in cairn-ui: the one `ui` names, or `pixi run ui` for a local
repository. Give the user the report's URL, `<ui>/p/<project>/r/<name>`.
