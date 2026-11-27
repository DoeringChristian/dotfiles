# Reproducibility checklist

Review the applicable items before a handoff that changes the project's setup,
evidence, or reports; mark unused cluster/hosting features not applicable.


Environment and runs
- [ ] The project is a Git repository whose scaffold, configs, and `pixi.lock`
      were committed before the first run; a fresh clone runs the documented
      pixi tasks on every listed platform.
- [ ] `.pixi/`, `.cairn/`, `outputs/`, `artifacts/`, and `data/` are ignored and
      excluded from formatting and other source tooling.
- [ ] Cairn is the pinned `cairn2[media,ui]` v0.18.0 dependency, imported as
      `cairn`; reports live in cairn-ui, not in the project or the repository.
      No Cairn internals are copied or patched; Settings live in `.cairn.toml`.
- [ ] No experiment-tracking service or custom run database is used; Cairn's
      repo (runs and artifacts) is the record.
- [ ] `experiments/run.py` and `experiments/research_cairn.py` come from the
      skill's assets; each entry point is a standard `@hydra.main` function
      using `with cairn.run(...) as run:` inside the function, with the name
      from config and an explicitly resolved config passed to Cairn.
      Hydra is installed separately; no Cairn resolver or callback is assumed.
- [ ] Hydra keeps job bookkeeping and optional scratch files under ignored `outputs/`; each job gets one full Cairn
      run ID. Studies retain their expected roster and are finalized explicitly
      only when every expected trial is present and completed.
- [ ] Every run records initial source, exact `pixi.lock`, resolved config,
      runtime inventory, and logs through native Cairn capture. Capture omissions
      and errors were inspected; required missing files (including Hydra runtime
      files when relevant) were explicitly added. Backend status is the completion
      record, and only completed, validated runs count as evidence.
- [ ] Run names describe the run and what it runs on, in the project's own
      terms (`ours-ai57_008-w64`): the names alone tell the runs apart, every
      variant and multirun trial has its own, a rerun of the same thing is the
      next version (no counters, dates, or `v2`/`final`); runs carry tags;
      descriptions explain purpose and interpretation limits.
- [ ] Runs split by computation: one per expensive computation (training,
      evaluation, preparation) and one analysis run per figure or table group,
      named after what it shows and covers and reading upstream runs with
      `run.use`; no numbered run names, and no variants hidden under one name.
- [ ] Each run logs images over steps of everything cheap to compute (output
      next to reference and input, error map, image-valued parameters and
      intermediate quantities) under stable keys, so it is inspectable in the
      UI without a report.
- [ ] Metrics and intermediate outputs are recorded during the run at a configured
      cadence, with stable fields and observation axes alongside media.
- [ ] Evidence is recorded with `run.log` and `run.add`. Separate result publication is optional. Reusable stage outputs remain on runs by default; a separate artifact
      has an independent identity/lifecycle purpose. Scientific tables
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
- [ ] Existing immutable archives use native links when appropriate; raw files
      are excluded from Git/provenance before the first run. Remote link/copy
      behavior is checked where duplicate storage is unacceptable.
- [ ] Downstream stages use exact producing runs and named outputs; invariant
      inputs are referenced rather than redundantly copied into every trial.
- [ ] Imported datasets have documented origin/validation, without a fabricated
      producer. Reports distinguish imported inputs from computed evidence.
- [ ] Every result a report shows was recorded on a completed, scientifically
      validated run. Any separately published result artifact has a verified
      completed producer. `latest` is the newest completed version, not a
      validated one: after a rerun, the claims that rest on it were re-read. No
      experiment output was disguised as an imported dataset.
- [ ] Datasets and models experiments read are artifacts, used with
      `run.use` (exact `@vN` refs in configs for cited evidence), so each
      run lists them as inputs.
- [ ] The project selects one local repo (created on first access) or a remote server
      in `.cairn.toml` or the environment. A remote is selected
      only for a server the user runs and named; the project namespace is
      separate from its URL. No token is in the repository, configs, scripts,
      logs, or the handoff.
- [ ] On a cluster: one `cairn --repo <path> server` on a local disk (never
      on a compute node or a shared filesystem), jobs target its URL and
      project with protected credentials, and outboxes are
      kept until sent (`cairn recover`); reads
      confirm completion and exact artifact availability before evidence handoff.

Method and evidence
- [ ] The user confirmed the method specification and consequential
      ambiguities.
- [ ] The method under study is tested on its own over the whole problem, not
      in a hybrid that hands its hard parts (a stage, region, case, or
      fallback) to the baseline or another method; any hybrid was requested by
      the user and is reported next to the pure method.
- [ ] The handoff states the project's stage (in principle, exploring
      approaches, or digging into one). While exploring, several approaches
      are compared on the same setup with their trade-offs, effort is not
      concentrated on the current leader, and untested alternatives or
      reformulations are suggested, not implemented without the user's
      agreement; the objective and problem statement are the user's.
- [ ] Each question was answered at the smallest setup that can answer it
      (proofs of concept in minutes); long runs state what no smaller setup
      could show and followed a passing small version and smoke run; claimed
      results are backed at the claimed scale, with the trend along the scale
      ladder and where the method breaks.
- [ ] Baselines run in their faithful configuration; a plain one is added and
      labelled only when the question needs it (the tuning does not transfer
      or hides the mechanism).
- [ ] Results are reported per setup, with the setup stated precisely and
      where each method is better and why; no result is generalized beyond
      the setups it was measured on.
- [ ] Faithful baselines and a bounded feasibility study precede tuning or
      large studies; studies use a multirun for separate experiments or a
      declared in-run grid for evaluation conditions, sized to the decision and
      the project's runtime budget.
- [ ] Reusable diagnostics keep one visual grammar per comparison family, and
      any change of chart is justified by a different question.

Reports
- [ ] In the user's reports, only what the user asked for was changed, where they
      asked; no sections were added or text restructured on my own.
- [ ] Existing reports were changed with `report edit`, or `report write --base`,
      on a text read right before; nothing the user wrote was lost.
- [ ] Each explored direction is an agent report opening with Claim / Setup
      where it holds / Status / Evidence, and the header matches the evidence
      below it.
- [ ] Direction reports follow the paper-like spine where the question needs
      it; inspection, validation, and comparison reports use the sections
      their question needs.
- [ ] The method and baselines are built from the framework's abstractions
      (Mitsuba plugins and Dr.Jit autodiff, PyTorch `nn.Module`s and
      `torch.optim`, ...); any departure is stated in Methods.
- [ ] Methods states the method as implemented (equations or an algorithm),
      with the figures a paper in the field would have (for a neural network,
      its architecture drawn from the model), and every changed direction
      report was reviewed against references/review.md; items left open are
      in the handoff.
- [ ] Background and related work comes from a literature and prior-art
      search with linked sources, and overlapping prior art is flagged in
      callouts explicitly headed "Prior art".
- [ ] Every method, baseline, and variant is defined, with its difference
      from the baseline, what is held constant, and the fairness boundary,
      before results use its name.
- [ ] No result number is typed into a report: every result is a table,
      value, or figure shown from a run, logged by an analysis run that
      `use`s what it reads; only design constants are typed. Table columns
      state the comparison, direction, population, and aggregation.
- [ ] The data each figure plots is stored in full on its run, so the
      analysis run can redraw it without rerunning an expensive stage.
- [ ] Methods has the figures a good paper would: an overview of the method,
      structure diagrams where the method has interacting parts, and the
      experiment setup (geometry drawn to scale from the resolved config, the
      real test data). Each is labelled with the symbols of the equations,
      explained in the text, and was rendered and inspected (aligned, no
      overlaps or clipped text, arrows reach their targets); no auto-laid-out
      graphs, no diagrams of the tooling or of linear protocol steps.
- [ ] Every figure the user asked for is in the report as asked, and the
      mechanisms the claim depends on are shown on a small instance with
      values from the project's code, not only through outputs or aggregates.
- [ ] Callouts mark only consequential synchronization needs and are revised
      when resolved.
- [ ] Every copied reference the user sent was found by its passage, and the
      answer said in the chat what changed.

Hosting
- [ ] cairn-ui binds to localhost by default and is not exposed unauthenticated
      to an untrusted network; the user's Cairn server was not touched.
- [ ] The handoff gives exact commands for the experiments, the report URLs
      (`<ui>/p/<project>/r/<name>`), and the run and artifact references the
      reports show.
