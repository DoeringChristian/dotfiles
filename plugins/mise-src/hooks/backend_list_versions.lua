--- From-source recipes pin one version (see registry.lua), so that's the only
--- installable version; `"src:stow" = "latest"` resolves to it.
function PLUGIN:BackendListVersions(ctx)
    local registry = require("registry")
    local t = registry[ctx.tool]
    if not t then
        error("src backend: unknown tool '" .. ctx.tool .. "' (not in registry.lua)")
    end
    return { versions = { t.version } }
end
