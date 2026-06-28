--- Resolve installable versions live from the app's GitHub releases feed (the
--- atom feed returns 200 without auth, dodging the API's anonymous rate limit).
--- So `"app:kitty" = "latest"` tracks upstream and any released version pins.
--- No versions/checksums are hand-maintained in registry.lua.
function PLUGIN:BackendListVersions(ctx)
    local cmd = require("cmd")
    local registry = require("registry")

    local app = registry[ctx.tool]
    if not app then
        error("app backend: unknown app '" .. ctx.tool .. "' (not in registry.lua)")
    end

    local feed = cmd.exec("curl -fsSL https://github.com/" .. app.repo .. "/releases.atom")

    -- Atom entries link to .../releases/tag/<tag>; take the tag, drop a leading
    -- "v", keep numeric versions only (skips "nightly" etc.). The atom feed is
    -- newest-first, but mise uses the RETURNED ORDER for backend plugins (no
    -- semver re-sort) and treats the LAST entry as "latest" -- so reverse to
    -- oldest-first, making the newest release the latest.
    local order, seen = {}, {}
    for tag in feed:gmatch('/releases/tag/([^"<]+)') do
        local v = tag:gsub("^v", "")
        if v:match("^%d[%d%._]*$") and not seen[v] then
            seen[v] = true
            table.insert(order, v)
        end
    end
    if #order == 0 then
        error("app backend: no releases found for " .. app.repo)
    end

    local versions = {}
    for i = #order, 1, -1 do versions[#versions + 1] = order[i] end
    return { versions = versions }
end
