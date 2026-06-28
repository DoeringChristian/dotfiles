-- registry.lua -- from-source recipes for the `src:` backend. The mise analog of
-- the dotfiles' pixi ext/<name> recipes: tools with no usable binary backend
-- (not on conda-forge / no GitHub release binary), built from source into mise's
-- install dir.
--
-- HERMETIC BUILD: like the old pixi recipes (which declared `requirements.build`
-- and got make/perl from conda-forge), the build runs under `mise x <build_tools>`
-- so the host needs NO make/perl/etc. — mise supplies them from conda-forge on
-- demand. Runtime interpreters that the tool needs (e.g. perl for stow) must be
-- regular mise tools in mise.toml so they're guaranteed on PATH.
--
-- Each entry:
--   version           -- pinned version (these are stable, low-churn tools)
--   fetch.kind        -- "tarball" (curl + tar -xz, strip top dir) or "git"
--   fetch.url         -- tarball URL (kind="tarball")
--   fetch.repo / ref  -- git URL + commit/tag (kind="git")
--   build_tools       -- conda specs supplied for the build via `mise x` (host-free)
--   build             -- shell snippet run in the source dir with $PREFIX exported

return {
  -- GNU stow: pure-Perl; the official tarball ships a working ./configure.
  -- Build tools (make/perl/texinfo) come from conda via mise x; the installed
  -- launchers' shebang is normalized to `/usr/bin/env perl` so they run on the
  -- conda:perl that mise.toml guarantees at runtime (NOT a host perl).
  stow = {
    version = "2.4.1",
    -- ftpmirror.gnu.org redirects to a fast nearby mirror (ftp.gnu.org is slow).
    fetch = { kind = "tarball", url = "https://ftpmirror.gnu.org/stow/stow-2.4.1.tar.gz" },
    -- make + perl only: the release tarball ships pre-built docs, so `make`
    -- never invokes makeinfo (verified) — no texinfo needed.
    build_tools = { "conda:make", "conda:perl" },
    build = [[./configure --prefix="$PREFIX" --with-pmdir="$PREFIX/share/perl5" && make && make install]],
  },

  -- passage: FiloSottile's age-based password store; `make install` just copies
  -- the scripts. Runtime deps (bash, age, git, tree) are all mise tools already.
  passage = {
    version = "1.7.4",
    fetch = { kind = "git", repo = "https://github.com/FiloSottile/passage.git",
              ref = "4e4c5ae14be91833791d45608f50868175c1490f" },
    build_tools = { "conda:make" },
    build = [[make install PREFIX="$PREFIX" WITH_ALLCOMP=yes]],
  },
}
