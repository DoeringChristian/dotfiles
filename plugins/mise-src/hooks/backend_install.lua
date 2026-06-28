--- Build a tool from source into mise's install dir (the pixi ext/ analog).
--- Fetches per the recipe (tarball or git), then runs the build snippet in the
--- source tree with $PREFIX = <install_path>. The build runs under `mise x
--- <build_tools>` so make/perl/etc. come from conda-forge — the HOST needs no
--- build toolchain (matching pixi's hermetic recipe builds).
function PLUGIN:BackendInstall(ctx)
    local registry = require("registry")
    local tool = ctx.tool
    local dest = ctx.install_path

    local t = registry[tool]
    if not t then
        error("src backend: unknown tool '" .. tool .. "' (not in registry.lua)")
    end

    local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

    -- fetch step (tarball or git) — curl/tar/git only (no build toolchain).
    local f = t.fetch
    local fetch_sh
    if f.kind == "tarball" then
        fetch_sh = 'curl -fsSL --retry 3 --connect-timeout 20 -o src.tgz ' .. q(f.url)
            .. ' && mkdir -p src && tar -xzf src.tgz -C src --strip-components=1'
    elseif f.kind == "git" then
        fetch_sh = 'git clone --quiet ' .. q(f.repo) .. ' src'
            .. ' && git -C src checkout --quiet ' .. q(f.ref)
    else
        error("src backend: unknown fetch kind '" .. tostring(f.kind) .. "' for " .. tool)
    end

    -- build step: run under `mise x <build_tools>` so make/perl/... are supplied
    -- from conda-forge on demand. The build snippet runs in the source dir with
    -- $PREFIX exported (inherited by the nested shell).
    local prefix = "mise x"
    for _, spec in ipairs(t.build_tools or {}) do
        prefix = prefix .. " " .. spec .. "@latest"
    end
    local build_sh
    if #(t.build_tools or {}) > 0 then
        build_sh = prefix .. " -- bash -c " .. q(t.build)
    else
        build_sh = t.build
    end

    local script = table.concat({
        "set -e",
        "PREFIX=" .. q(dest),
        "export PREFIX",
        'mkdir -p "$PREFIX/bin"',
        'WORK=$(mktemp -d)',
        'trap \'rm -rf "$WORK"\' EXIT',
        'cd "$WORK"',
        fetch_sh,
        'cd src',
        build_sh,
        -- Normalize any installed Perl launcher's shebang to on-PATH perl, so it
        -- runs on the conda:perl that mise.toml guarantees (not the ephemeral
        -- build perl, and not a host perl). No-op for non-Perl tools.
        'for b in "$PREFIX"/bin/*; do [ -f "$b" ] || continue; '
            .. 'if head -1 "$b" | grep -q "perl"; then '
            .. 'sed "1s|^#!.*perl.*|#!/usr/bin/env perl|" "$b" > "$b.tmp" && '
            .. 'cat "$b.tmp" > "$b" && rm -f "$b.tmp"; fi; done',
    }, "\n")

    local ok = os.execute(script)
    if not (ok == true or ok == 0) then
        error("src backend: build of " .. tool .. " failed (os.execute=" .. tostring(ok) .. ")")
    end
    return {}
end
