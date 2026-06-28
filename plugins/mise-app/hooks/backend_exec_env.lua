--- Expose <install_path>/bin (the app launchers) on PATH.
function PLUGIN:BackendExecEnv(ctx)
    local file = require("file")
    return {
        env_vars = {
            { key = "PATH", value = file.join_path(ctx.install_path, "bin") },
        },
    }
end
