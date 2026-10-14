# Reproducibility checklist

Go through it before a handoff that changes the project's setup, evidence, or reports.


Environment and runs
- [ ] The project is a Git repository whose scaffold, configs, and `pixi.lock`
      were committed before the first run; a fresh clone runs the documented
      pixi tasks on every listed platform.
- [ ] `.pixi`, `outputs/`, and `generated/` are ignored and excluded from
      formatting and other source tooling.
- [ ] `reports/` holds only report content; the report tooling is the pinned
      `cairn-report` dependency, with no copied or patched tooling in the
      project and style changes only through `cairn-report.toml`.
- [ ] No experiment-tracking service or custom run database is used.
- [ ] `experiments/run.py` and `provenance/source_snapshot.py` are copied
      from the skill's assets as writable files; the logger is imported from
      `cairn_report.logger`, not copied.
- [ ] Every run has `.hydra/` configs, `run.json` (the single completion
      contract), and bounded `provenance/`; only `completed` runs count as
      evidence, and a failed snapshot fails the run.
- [ ] `latest` moves only to completed runs, and to a study only when every
      trial completed; reports record resolved timestamp paths.
- [ ] Run names are concise semantic slugs, and descriptions explain purpose
      and interpretation limits.
- [ ] Evidence is written through `RunLogger`; `metrics.jsonl` and
      `artifacts.jsonl` are append-only and name the code that logged and drew
      each file.
- [ ] `linux-64` is a locked platform, `experiments/cluster.sh` and
      `experiments/finalize_study.py` are copied from the slurm skill's assets,
      each used cluster's profile and launchers from its skill, and every
      cluster study ran through `pixi run <cluster> ...` after the
      GPU-efficiency gate.
- [ ] If the project uses a hub: no token in the repository or handoff, and
      remote jobs run through `cairn-report push runs --watch -- ...` (on a
      cluster, via `pixi run <cluster> submit`/`pack`).

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
- [ ] The overview (`reports/report.md`) has Introduction (the shared target
      every direction builds on), Status (cross-direction state, the next
      decision, and proposed directions), and Research directions (a `reports`
      fence).
- [ ] Each research direction has its own `reports/<slug>/report.md` with a
      current front matter `summary`, shown on its page and in the overview;
      related reports cross-link with checked `report:` links (`report:/` for
      the overview).
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
- [ ] Every metric card and `{{ value }}` is computed from tracked run files;
      the build's typed-number list holds only design constants; metric labels
      state the comparison, direction, population, and aggregation.
- [ ] Experimental figures come from the runs that wrote them (`run:` paths),
      only from completed runs, and each one's provenance is shown in the
      lightbox.
- [ ] A diagram, where one is needed, shows the model as a graph (its
      variables and terms, labelled as in the equations), is explained in the
      text, and is a Graphviz fence; no diagrams of the report or run tooling
      or of linear protocol steps.
- [ ] `!!! finding` blocks carry a valid status and a qualitative title (no
      result numbers), cite source runs and comment ids, and expose conflicts.
- [ ] Callouts mark only consequential synchronization needs and are revised
      when resolved.
- [ ] Each report build has a manifest hashing everything it read, its
      builder, templates, and runtime.

Comments and hosting
- [ ] `cairn-report.toml` sets the `[page] copy_preamble` with the comment
      handling instructions; pasted comments are handled by quote, rebuilt,
      and summarized per comment id.
- [ ] The report server binds to localhost by default and is not exposed
      unauthenticated to an untrusted network.
- [ ] Shared or published reports are the unchanged `generated/reports/`
      output; nothing was restyled or re-authored for the destination.
- [ ] The handoff gives exact build, serve, and host commands, concrete URLs,
      and the locations of run data, comments, and findings.
