# Reproducibility checklist

Review the applicable items before a handoff that changes the project's setup,
evidence, or reports; mark unused cluster/hosting features not applicable.


Environment and runs
- [ ] The project is a Git repository whose scaffold, configs, and `pixi.lock`
      were committed before the first run; a fresh clone runs the documented
      pixi tasks on every listed platform.
- [ ] `.pixi/`, `.cairn/`, `outputs/`, `artifacts/`, and `data/` are ignored and
      excluded from formatting and other source tooling.
- [ ] `reports/` holds only report sources; Cairn is the pinned
      `cairn2[reports,media,ui]` v0.11.0 dependency, imported as `cairn`.
      No Cairn internals are copied or patched; entry points use Cairn’s native tracking APIs. Settings live in `.cairn.toml`; no JSON `.cairn` file is assumed.
- [ ] No experiment-tracking service or custom run database is used; Cairn's
      repo (runs and artifacts) is the record.
- [ ] `experiments/run.py` and `experiments/research_cairn.py` come from the
      skill's assets; each entry point is a standard `@hydra.main` function
      using `with cairn.init(...) as run:` inside the function, with the name
      from config and an explicitly resolved config passed to Cairn.
      Hydra is installed separately; no removed resolver/callback is imported.
- [ ] Hydra keeps job bookkeeping and optional scratch files under ignored `outputs/`; each job gets one full Cairn
      run ID. Studies retain their expected roster and are finalized explicitly
      only when every expected trial is present and completed.
- [ ] Every run records initial source, exact `pixi.lock`, resolved config,
      runtime inventory, and logs through native Cairn capture. Capture omissions
      and errors were inspected; required missing files (including Hydra runtime
      files when relevant) were explicitly added. Backend status is the completion
      record, and only completed, validated runs count as evidence.
- [ ] Run names are concise semantic slugs, and descriptions explain purpose
      and interpretation limits.
- [ ] Evidence is recorded with `run.log`, `run.track`, and
      `run.add`. Separate result publication is optional. Scientific tables
      and arrays are retained completely,
      and the producer's provenance identifies the source and environment.
- [ ] Every expensive stage (training, fitting, rendering, simulation,
      evaluation) stores its complete output: per-sample and per-point values,
      not only aggregates or pictures. Every figure, table, and reported number
      can be recomputed from stored records by cheap code without rerunning
      that stage; anything that cannot is fixed and rerun before it is cited.
- [ ] If using a GPU cluster: `linux-64` is a locked platform; `experiments/cluster.sh` and other
      scheduler files come from the relevant skills, and their legacy Cairn
      calls have been adapted and tested before use. Each used cluster's
      profile and launchers come from its skill, and every
      cluster study ran through `pixi run <cluster> ...` after the
      GPU-efficiency gate.

Artifacts and repo
- [ ] Every result a report cites was recorded on a completed, scientifically
      validated run. Any separately published result artifact has a verified
      completed producer. `latest` is
      not a success filter; exact versions are pinned. No experiment output
      was published through the run-less explicit-project import API.
- [ ] Datasets and models experiments read are artifacts, used with
      `run.use` (exact `@vN` refs in configs for cited evidence), so each
      run lists them as inputs.
- [ ] The project selects one local repo (created on first access) or a remote server
      through the current configuration API/environment. A remote is selected
      only for a server the user runs and named; the project namespace is
      separate from its URL. No token is in the repository, configs, scripts,
      logs, or the handoff.
- [ ] On a cluster: one `cairn --repo <path> server` on a local disk (never
      on a compute node or a shared filesystem), jobs target its URL and
      project with protected credentials, and durable client journals are
      retained until acknowledged. `Client.recover()` retries them; backend reads
      confirm completion and exact artifact availability before evidence handoff.

Method and evidence
- [ ] The user confirmed the method specification and consequential
      ambiguities.
- [ ] Faithful baselines and a bounded feasibility study precede tuning or
      large studies; studies use a multirun for separate experiments or a
      declared in-run grid for evaluation conditions, sized to the decision and
      the project's runtime budget.
- [ ] Reusable diagnostics keep one visual grammar per comparison family, and
      any change of chart is justified by a different question.

Reports
- [ ] Each research direction has its own single-page
      `reports/<slug>/report.md` (no root report, no nesting) with a current
      front matter `title` and `description`, with scientific status and
      synthesis in its body; related reports cross-link with checked URLs
      and explicit anchors in the native reader and standalone export.
- [ ] Each direction report follows the paper-like spine: Abstract,
      Introduction, Background and related work, Methods, results and
      discussion, Conclusion.
- [ ] The method and baselines are built from the framework's abstractions
      (Mitsuba plugins and Dr.Jit autodiff, PyTorch `nn.Module`s and
      `torch.optim`, ...); any departure is stated in Methods.
- [ ] Methods states the method as implemented (equations or an algorithm),
      with the figures a paper in the field would have (for a neural network,
      its architecture drawn from the model), and every changed direction
      report was reviewed against references/review.md; items left open are in the handoff.
- [ ] Background and related work comes from a literature and prior-art
      search with linked sources, and overlapping prior art is flagged in
      supported callouts explicitly headed "Prior art".
- [ ] Every method, baseline, and variant is defined, with its difference
      from the baseline, what is held constant, and the fairness boundary,
      before results use its name.
- [ ] Every report declares what it reads under `cairn.inputs:`; references a
      finding relies on are pinned (`artifacts/<name>@vN`, `runs/<name>@vN`, or full artifact IDs), and report code reads no undeclared
      experimental results. This is a workflow check, not an engine sandbox.
- [ ] Every metric card and result in prose is generated from the declared
      inputs; only design constants are typed into the scientific text;
      metric labels state the comparison, direction, population, and
      aggregation.
- [ ] Experimental figures come from the runs that wrote them
      through declared captured inputs, only from completed, validated
      producers, and their exact source refs and input hashes are inspectable.
      The data each figure plots is stored in full under its key and the report
      redraws it from that data; the generating function and material plotting
      settings are recorded alongside, with source provenance.
- [ ] Methods has the figures a good paper would: an overview of the method,
      structure diagrams where the method has interacting parts, and the
      experiment setup (geometry drawn to scale from the resolved config, the
      real test data). Each is labelled with the symbols of the equations,
      explained in the text, and was rendered and inspected (aligned, no
      overlaps or clipped text, arrows reach their targets); no auto-laid-out
      graphs, no diagrams of the report or run tooling or of linear protocol
      steps.
- [ ] `::: {.finding}` blocks state tentative/supported/contradicted/superseded
      explicitly, have a qualitative title (no result numbers), cite source
      artifacts, and expose conflicts.
- [ ] Callouts mark only consequential synchronization needs and are revised
      when resolved.
- [ ] Each successful report build has `manifest.json` with exact input refs,
      captured source hashes, exact input IDs, and environment provenance.
      Undeclared external reads are not tracked; the report obeys the stricter
      declared-input policy and does not claim hermetic execution.
- [ ] Every changed report is published (`pixi run report-publish <slug>`),
      so its version records the exact inputs.

Hosting
- [ ] Pasted copy-location markers (`reports/<slug>/report.md:42 "..."`) are
      located by file, line, or figure id, handled, rebuilt, and summarized
      per marker.
- [ ] The report server and the UI bind to localhost by default and are not
      exposed unauthenticated to an untrusted network.
- [ ] Shared or published reports are the unchanged Cairn output
      (`.cairn/share/<slug>/`, `.cairn/build/`, or the published
      report version); nothing was restyled or re-authored for the destination.
- [ ] The handoff gives exact build, publish, serve, and UI commands, concrete
      URLs, the run and artifact references the reports read, and the
      locations of run data and findings.
