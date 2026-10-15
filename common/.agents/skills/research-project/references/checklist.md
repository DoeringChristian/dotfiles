# Reproducibility checklist

Go through it before a handoff that changes the project's setup, evidence, or reports.


Environment and runs
- [ ] The project is a Git repository whose scaffold, configs, and `pixi.lock`
      were committed before the first run; a fresh clone runs the documented
      pixi tasks on every listed platform.
- [ ] `.pixi` and `data/` are ignored (`.cairn/` ignores itself) and
      excluded from formatting and other source tooling.
- [ ] `reports/` holds only report content; Cairn is the pinned `cairn`
      dependency, with no copied or patched tooling in the project and style
      changes only through `cairn.toml`.
- [ ] No experiment-tracking service or custom run database is used; Cairn's
      store (runs and artifacts) is the record.
- [ ] `experiments/run.py` is the thin entry point from the skill's assets;
      the run bookkeeping and snapshot callback are imported from Cairn
      (`cairn.runs.hydra`, `cairn.runs.snapshot`), not copied.
- [ ] `hydra.run.dir` and `hydra.sweep.dir` are `${cairn.run:...}`, so every
      Hydra job is one version of `runs/<run-name>`; a sweep is one run per
      trial plus a summary run from `StudyCompletion`.
- [ ] Every run has `.hydra/` configs, `provenance/` (or `code/`),
      `environment/`, and logs; the version's status is the completion record
      and only completed versions count as evidence; a failed snapshot fails
      the run.
- [ ] Run names are concise semantic slugs, and descriptions explain purpose
      and interpretation limits.
- [ ] Evidence is added through `run.add` / `add_*` on the run or a
      `cairn.draft`; `metrics.jsonl` and `artifacts.jsonl` are append-only and
      name the code that added each file.
- [ ] `linux-64` is a locked platform, `experiments/cluster.sh` and
      `experiments/finalize_study.py` are copied from the slurm skill's assets,
      each used cluster's profile and launchers from its skill, and every
      cluster study ran through `pixi run <cluster> ...` after the
      GPU-efficiency gate.

Artifacts and store
- [ ] Every result a report cites is a draft (`cairn.draft`) written by a
      completed run, so it has that run as its input; failed runs leave no
      version a report could resolve, and no experiment output was published
      by hand with `cairn publish`.
- [ ] Datasets and models experiments read are artifacts, used with
      `cairn.use` (exact versions in configs for cited evidence), so each
      run lists them as inputs.
- [ ] `cairn.toml` names the store (`[store] path`, or the user's server in
      `[store] url`) and project; no token is in the repository, configs,
      scripts, logs, or the handoff.
- [ ] With a store server and a cluster: one `cairn server` on a local disk
      (never a store folder on a shared filesystem written by several
      machines), jobs publish over HTTP with `CAIRN_STORE_TOKEN` from the
      environment, the local queue on persistent storage, `CAIRN_CACHE_DIR`
      on node-local scratch, `cairn sync` at the end of each job, and
      `cairn status` shows nothing waiting.

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
      front matter `title`, `status`, and `summary`, as shown in the index and
      the UI; related reports cross-link with checked `report:<slug>#anchor`
      links.
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
      `prior-art` callouts.
- [ ] Every method, baseline, and variant is defined, with its difference
      from the baseline, what is held constant, and the fairness boundary,
      before results use its name.
- [ ] Every report declares what it reads under `inputs:`; references a
      finding relies on are pinned (`@vN` or a deliberately moved alias), and
      the build reads nothing undeclared.
- [ ] Every metric card and `{{ value }}` is computed from the declared
      inputs; the build's typed-number list holds only design constants;
      metric labels state the comparison, direction, population, and
      aggregation.
- [ ] Experimental figures come from the runs that wrote them
      (`input:<name>/...`), only from completed artifact versions, and each
      one's provenance is shown in the lightbox.
- [ ] A diagram, where one is needed, shows the model as a graph (its
      variables and terms, labelled as in the equations), is explained in the
      text, and is a Graphviz fence; no diagrams of the report or run tooling
      or of linear protocol steps.
- [ ] `!!! finding` blocks carry a valid status and a qualitative title (no
      result numbers), cite source artifacts, and expose conflicts.
- [ ] Callouts mark only consequential synchronization needs and are revised
      when resolved.
- [ ] Each report build has a manifest with the exact input versions and the
      hashes of everything it read, its builder, templates, and runtime.
- [ ] Every changed report is published (`pixi run publish reports/<slug>`),
      so its version records the exact inputs.

Hosting
- [ ] Pasted copy-location markers (`reports/<slug>/report.md:42 "..."`) are
      located by file, line, or figure id, handled, rebuilt, and summarized
      per marker.
- [ ] The report server and the UI bind to localhost by default and are not
      exposed unauthenticated to an untrusted network.
- [ ] Shared or published reports are the unchanged Cairn output
      (`.cairn/share/index.html`, `.cairn/build/`, or the published
      report version); nothing was restyled or re-authored for the destination.
- [ ] The handoff gives exact build, publish, serve, and UI commands, concrete
      URLs, the run and artifact references the reports read, and the
      locations of run data and findings.
