# tests

Docker-based tests for the bootstrap on clean Linux machines. Requires `docker`
(or `DOCKER=podman tests/run.sh ...`).

```bash
tests/run.sh                 # ubuntu, fast smoke test (default)
tests/run.sh fedora          # other distro
tests/run.sh ubuntu --full   # build every ext/ source package (slow, ~15-20 min)
tests/run.sh ubuntu --remote # run the real `curl | bash` from origin/main
```

## What it does

Each run spins a fresh container and:

1. starts from a bare image (often without `git`/`curl`) so the bootstrap's
   prerequisite install is exercised,
2. runs `bootstrap.sh` → `setup.sh` → `sync.sh` (with `SKIP_SECRETS=1`, so it
   doesn't prompt for the age passphrase),
3. asserts the core tools (`rg`, `fish`, `stow`, `git`) are on `~/.pixi/bin` and
   that stow linked `~/.config/fish/config.fish`.

## Modes

| Mode | Source | Manifest | Speed |
|---|---|---|---|
| (default) smoke | local working tree | `tests/fixtures/minimal-global.toml` (channel pkgs only) | ~minutes |
| `--full` | local working tree | the real `pixi-global.toml` (builds kitty/tev/neovim/…) | ~15-20 min |
| `--remote` | `curl \| bash` from origin/main | real `pixi-global.toml` (+ clone + git-lfs) | slow |

The local modes copy the working tree in, so they test **uncommitted** changes.
`--remote` tests what's pushed to `main` — it also exercises the `git clone` and
`git lfs pull` paths that the local copy skips.

Supported distros: `ubuntu`, `debian`, `fedora`, `arch` (glibc; musl/alpine isn't
supported by pixi's toolchain).
