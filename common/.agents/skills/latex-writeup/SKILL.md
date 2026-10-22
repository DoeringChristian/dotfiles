---
name: latex-writeup
description:
  Set up and write a lab LaTeX problem writeup (a short research memo with Problem, Notation, Background, Approach,
  Open questions, References) as a pixi project built with latexmk and pdflatex from Homebrew's TeX Live. Use
  when the user wants a LaTeX writeup, memo, problem statement, or short technical note, or asks to build or fix
  one made from this template. Never use tectonic, xelatex, or lualatex for these.
---

# LaTeX problem writeup

A writeup is a small pixi project. pixi only runs the build: TeX comes from Homebrew's `texlive` formula, because
conda-forge's `texlive-core` has the TeX programs but no LaTeX packages, and tectonic (xelatex) changes the
formatting. The engine is always pdflatex, through latexmk.

## Set up

1. Check TeX: `brew list texlive >/dev/null 2>&1 || brew install texlive` (about 5 GB; it is in the dotfiles'
   `Brewfile.workstation`, so `./update.sh` on a workstation installs it). Ask before installing it.
2. Copy the template into the target directory (a new directory, or `writeup/` inside an existing project; a
   nested `pixi.toml` is fine):
   ```bash
   T=~/.agents/skills/latex-writeup/assets
   cp -R "$T"/. <dir>/ && mv <dir>/gitignore <dir>/.gitignore
   ```
3. In `pixi.toml` replace `WRITEUP_NAME` (directory name, kebab-case). In `main.tex` replace `TITLE` and
   `AUTHOR` (the user's name from `git config user.name` unless they give another).
4. `pixi run build` must succeed before you hand it back (`git init` and a first commit if the directory is new
   and not in a repo; commit `pixi.lock`).

| Task | Does |
|---|---|
| `pixi run build` | `latexmk`: pdflatex + BibTeX as often as needed → `build/main.pdf` |
| `pixi run watch` | rebuild on save and open the PDF viewer (`latexmk -pvc`); leave it to the user, it never exits |
| `pixi run clean` | remove build products |
| `pixi run check-tex` | show where the main packages resolve; run when a build cannot find a package |
| `pixi run fmt` | format `main.tex` and `macros.tex` in place with latexindent (backups and `indent.log` in `build/`) |
| `pixi run fmt-check` | exit 1 if a file is not formatted |

`scripts/tex.sh` puts `$(brew --prefix texlive)/bin` first on PATH so no other TeX (MacTeX, a conda env) is used.
`latexmkrc` fixes the engine, the output directory `build/`, and `main.tex` as the only target. The formatter is
`latexindent.pl` from conda-forge (the one pixi dependency) with `.latexindent.yaml`, the lab's paper config: one
sentence per line, wrapped at 80 columns, abbreviations like "e.g." and "i.e." not treated as sentence ends.

## Files

- `main.tex`: the preamble and the five sections. Each section has a comment saying what belongs in it; replace
  the comment with the text. Add sections only when the content does not fit the five.
- `macros.tex`: theorem environments (`theorem`, `lemma`, `proposition`, `definition`, `assumption`, `remark`)
  and notation (`\R`, `\E`, `\argmin`, `\abs{}`, `\norm{}`, `\vect{}`, `\mat{}`, `\todo{}`). Put new notation
  here as macros instead of repeating raw symbols.
- `refs.bib`: BibTeX entries, cited with `\citet{key}` (Jakob et al. [1]) or `\citep{key}` ([1]). Use real
  entries from DBLP, the publisher, or the paper's page; never invent bibliographic data.
- `figures/`: PDF (vector) or PNG figures, included by bare name: `\includegraphics[width=\linewidth]{name}`.

## Writing rules

- Reference with `\cref{...}` and label everything referenced: `sec:`, `eq:`, `fig:`, `tab:`, `def:`, `thm:`.
  Define theorem-like environments only with `\declaretheorem` (thmtools); plain `\newtheorem` with a shared
  counter makes cleveref print the wrong name.
- Packages: before adding one, check it resolves (`bash scripts/tex.sh kpsewhich <pkg>.sty`). Do not add
  `fontspec`, `unicode-math`, or anything needing xelatex/lualatex, and do not switch to biblatex (Homebrew's
  TeX Live has no `biber`).
- A build is clean when `build/main.log` has no `undefined` references or citations and no LaTeX warnings beyond
  the empty-bibliography one before the first citation (`grep -i -E 'warning|undefined' build/main.log`).
  Fix overfull boxes that visibly stick into the margin.
- Leave no `\todo{}` in a version the user means to share, unless they ask for it.
- Run `pixi run fmt` after editing, before building; one sentence per line keeps diffs and reviews readable. Add
  any new `.tex` file to both `fmt` tasks in `pixi.toml`.
- On a build error, read the first `file:line: error` in `build/main.log`, not latexmk's summary.
