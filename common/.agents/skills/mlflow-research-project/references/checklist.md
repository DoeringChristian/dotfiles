# Reproducibility checklist

Go through it before a handoff that changes the project's setup, evidence, or reports.


Environment and runs
- [ ] The scaffold, configs and pixi.lock are committed; a fresh clone runs
      documented tasks on supported platforms.
- [ ] Environments, data, tracking stores, job folders and generated report
      outputs are ignored and excluded from source tooling.
- [ ] Folio is a dependency, not copied/patched renderer code; style changes
      are made only when requested, through folio.toml.
- [ ] MLflow is the experiment record; no parallel custom tracking database.
- [ ] The entry point composes Hydra config, starts the MLflow run, logs
      provenance, instantiates the Experiment and invokes it.
- [ ] Each Hydra job has a separate folder and MLflow run ID; studies record
      exact trial IDs, statuses, selection rules and failed trials.
- [ ] Runs log resolved config and overrides, exact source revision (and patch
      or snapshot when needed), lock/environment, inputs, diagnostics and logs.
- [ ] Run names are concise and semantic; descriptions explain purpose and
      interpretation limits. Exceptions propagate and produce FAILED runs.
- [ ] Scalar histories go to MLflow; report-ready JSON/CSV, curves and figures
      are logged under a stable artifact directory such as evaluation/.
- [ ] Remote work uses the relevant cluster skills, locked linux-64 support,
      efficiency gates and MLflow-compatible launchers/finalizers.

Artifacts and tracking
- [ ] Cited results come from exact run IDs with FINISHED status, verified
      explicitly; Folio's adapter is not assumed to check status.
- [ ] Dataset/model identity, split, preprocessing and parent artifact URIs
      are recorded; data remains available for reproduction.
- [ ] Tracking URI is consistent across jobs, artifact downloads and reports;
      remote workers can upload and the report machine can download.
- [ ] Local SQLite is not shared across cluster jobs on a network filesystem;
      remote jobs use the user's tracking server and durable artifact store.
- [ ] Credentials are outside configs, repository, scripts, logs and handoff;
      tracking failures are visible, not treated as an offline sync guarantee.
- [ ] Cited artifacts are preserved and not overwritten; new evidence uses
      new runs. Report manifests preserve observed input content hashes.

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
      the generated index; related reports cross-link with checked Folio links.
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
      finding relies on are pinned to exact MLflow run IDs, and
      the build reads nothing undeclared.
- [ ] Every metric card and `{{ value }}` is computed from the declared
      inputs; the build's typed-number list holds only design constants;
      metric labels state the comparison, direction, population, and
      aggregation.
- [ ] Experimental figures come from the runs that wrote them
      (`input:<name>/...`), only from FINISHED runs, and each
      one has traceable run/file provenance.
- [ ] A diagram, where one is needed, shows the model as a graph (its
      variables and terms, labelled as in the equations), is explained in the
      text, and is a Graphviz fence; no diagrams of the report or run tooling
      or of linear protocol steps.
- [ ] `!!! finding` blocks carry a valid status and a qualitative title (no
      result numbers), cite source artifacts, and expose conflicts.
- [ ] Callouts mark only consequential synchronization needs and are revised
      when resolved.
- [ ] Each report build has a manifest with the exact input references and content hashes and the
      hashes of everything it read, its builder, templates, and runtime.
- [ ] Every changed report is rebuilt with Folio, checked by the report gate,
      and reviewed against R0–R9; export/distribute unchanged output when requested.

Hosting
- [ ] Pasted copy-location markers (`reports/<slug>/report.md:42 "..."`) are
      located by file, line, or figure id, handled, rebuilt, and summarized
      per marker.
- [ ] The report server and MLflow UI bind to localhost by default and are not
      exposed unauthenticated to an untrusted network.
- [ ] Shared or published reports are the unchanged Folio output
      (the standalone HTML export or complete configured build directory); nothing was restyled or re-authored for the destination.
- [ ] The handoff gives exact experiment, build, export, serve and tracking UI commands, concrete
      URLs, the run and artifact references the reports read, and the
      locations of run data and findings.
