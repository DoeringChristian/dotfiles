--- Install a GUI app from its sha256-pinned official prebuilt binary.
--- Mirrors the dotfiles' pixi ext/<name> recipes: download the per-platform
--- artifact, verify the checksum, lay out <install_path>/bin + libexec, and
--- create a desktop launcher (.app shim on macOS / .desktop on Linux).
function PLUGIN:BackendInstall(ctx)
    local cmd = require("cmd")
    local registry = require("registry")

    local tool = ctx.tool
    local version = ctx.version
    local dest = ctx.install_path

    local app = registry[tool]
    if not app then
        error("app backend: unknown app '" .. tool .. "' (not in registry.lua)")
    end

    -- Resolve the current platform key ("<os>-<arch>").
    local function sh(c) return (cmd.exec(c):gsub("%s+$", "")) end
    local os_key = (sh("uname -s") == "Darwin") and "darwin" or "linux"
    local m = sh("uname -m")
    local arch_key
    if m == "arm64" or m == "aarch64" then
        arch_key = "arm64"
    elseif m == "x86_64" or m == "amd64" then
        arch_key = "amd64"
    else
        error("app backend: unsupported architecture '" .. m .. "'")
    end
    local key = os_key .. "-" .. arch_key
    local p = app.platforms[key]
    if not p then
        error("app backend: no binary recorded for '" .. tool .. "' on " .. key)
    end

    -- Shell-quote helper (single-quote, escape embedded quotes).
    local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

    -- Build the download URL from the template (just substitute the version).
    local url = p.url:gsub("{version}", version)

    -- Common prologue: download the artifact from GitHub over HTTPS into $DEST.
    -- No checksum: integrity rests on HTTPS (see registry.lua header).
    local pre = table.concat({
        "set -e",
        "DEST=" .. q(dest),
        "URL=" .. q(url),
        'mkdir -p "$DEST/bin" "$DEST/libexec" "$DEST/Menu"',
        'cd "$DEST"',
        'curl -fsSL -o artifact "$URL"',
    }, "\n") .. "\n"

    -- Per-bin launcher line builder.
    --   wrapper (macOS .app): a tiny exec shim (a bare symlink trips kitty #1539).
    --   symlink (txz/appimage): relative symlink into libexec.
    local function bin_wrappers(prefix_path)  -- prefix_path = path to .app bundle
        local lines = {}
        for name, rel in pairs(p.binpaths) do
            table.insert(lines,
                "printf '#!/bin/sh\\nexec \"%s\" \"$@\"\\n' "
                .. q(prefix_path .. "/" .. rel)
                .. ' > "$DEST/bin/' .. name .. '"; chmod +x "$DEST/bin/' .. name .. '"')
        end
        return table.concat(lines, "\n")
    end

    local body
    if p.format == "dmg" then
        body = table.concat({
            "APP=" .. q(p.app),
            'rm -rf mnt && mkdir -p mnt',
            'hdiutil attach -nobrowse -noverify -noautoopen -mountpoint "$DEST/mnt" artifact >/dev/null',
            'rm -rf "$DEST/libexec/$APP"',
            'cp -R "$DEST/mnt/$APP" "$DEST/libexec/$APP"',
            'hdiutil detach "$DEST/mnt" -quiet || hdiutil detach "$DEST/mnt"',
            'rm -rf mnt artifact',
            'xattr -dr com.apple.quarantine "$DEST/libexec/$APP" 2>/dev/null || true',
            -- absolute install path baked in (the wrapper runs later, when $DEST is unset)
            bin_wrappers(dest .. "/libexec/" .. p.app),
            p.icon and ('cp "$DEST/libexec/$APP/' .. p.icon .. '" "$DEST/Menu/' .. tool .. '.icns" 2>/dev/null || true') or "",
        }, "\n")
    elseif p.format == "txz" then
        local links = {}
        for name, rel in pairs(p.binpaths) do
            table.insert(links, 'ln -sf "../libexec/' .. tool .. '/' .. rel .. '" "$DEST/bin/' .. name .. '"')
        end
        body = table.concat({
            'rm -rf "$DEST/libexec/' .. tool .. '" && mkdir -p "$DEST/libexec/' .. tool .. '"',
            'tar -xJf artifact -C "$DEST/libexec/' .. tool .. '"',
            'rm -f artifact',
            table.concat(links, "\n"),
            p.icon and ('cp "$DEST/libexec/' .. tool .. '/' .. p.icon .. '" "$DEST/Menu/' .. tool .. '.png" 2>/dev/null || true') or "",
        }, "\n")
    elseif p.format == "appimage" then
        -- --appimage-extract needs no FUSE; keep the AppDir, symlink the real bin.
        local binname = next(p.binpaths) and p.binpaths[next(p.binpaths)] or tool
        body = table.concat({
            'chmod +x artifact',
            'rm -rf "$DEST/libexec/' .. tool .. '" squashfs-root',
            './artifact --appimage-extract >/dev/null',
            'mv squashfs-root "$DEST/libexec/' .. tool .. '"',
            'rm -f artifact',
            'REAL=$(cd "$DEST/libexec/' .. tool .. '" && find . -type f -name ' .. q(binname)
                .. " -path '*bin/*' | head -1); REAL=${REAL#./}",
            '[ -n "$REAL" ] || REAL=$(cd "$DEST/libexec/' .. tool .. '" && find . -type f -name '
                .. q(binname) .. ' | head -1); REAL=${REAL#./}',
            'ln -sf "../libexec/' .. tool .. '/$REAL" "$DEST/bin/' .. tool .. '"',
            p.icon and ('ICON=$(find "$DEST/libexec/' .. tool .. '" -name ' .. q(p.icon)
                .. ' | head -1); [ -n "$ICON" ] && cp "$ICON" "$DEST/Menu/' .. tool .. '.png" || true') or "",
        }, "\n")
    else
        error("app backend: unknown format '" .. tostring(p.format) .. "' for " .. tool)
    end

    local ok = os.execute(pre .. body)
    if not (ok == true or ok == 0) then
        error("app backend: install of " .. tool .. " failed (os.execute=" .. tostring(ok) .. ")")
    end

    -- Desktop launcher (menuinst equivalent). Best-effort: never fail the tool
    -- install over a launcher hiccup. Skippable / relocatable via env vars.
    if os.getenv("MISE_APP_NO_LAUNCHER") ~= "1" then
        local lok, lerr = pcall(function()
            install_launcher(os_key, tool, dest, app.launcher, p)
        end)
        if not lok then
            print("app backend: launcher for " .. tool .. " skipped (" .. tostring(lerr) .. ")")
        end
    end

    return {}
end

--- Create a GUI launcher pointing at <dest>/bin/<exec>.
---   macOS: a shim .app under ~/Applications (Spotlight-indexable).
---   Linux: a .desktop under ~/.local/share/applications.
--- MISE_APP_LAUNCHER_DIR overrides the destination directory (used by tests).
function install_launcher(os_key, tool, dest, L, p)
    local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
    local exec = dest .. "/bin/" .. (L.exec or tool)
    local display = L.display or tool

    if os_key == "darwin" then
        local appsdir = os.getenv("MISE_APP_LAUNCHER_DIR") or (os.getenv("HOME") .. "/Applications")
        if p.app then
            -- The app shipped a REAL macOS .app bundle (e.g. kitty.app from the
            -- .dmg). Install that bundle itself into ~/Applications so Spotlight /
            -- Launch Services index and launch it exactly like a normally-dragged
            -- app (it's complete and code-signed) — far more robust than a shim
            -- whose executable is an unsigned shell script. `lsregister -f`
            -- registers it immediately so it shows up without waiting for a scan.
            local src = dest .. "/libexec/" .. p.app
            local dst = appsdir .. "/" .. p.app
            local lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
                .. "LaunchServices.framework/Support/lsregister"
            local script = table.concat({
                "set -e",
                "SRC=" .. q(src),
                "DST=" .. q(dst),
                'mkdir -p ' .. q(appsdir),
                'rm -rf "$DST"',
                -- ditto (not cp -R) is the macOS-correct way to copy a bundle:
                -- preserves the code signature, symlinks and metadata intact.
                'ditto "$SRC" "$DST"',
                'xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true',
                -- register with Launch Services + force a Spotlight import so it
                -- shows up / launches immediately (mdls is empty until imported).
                '[ -x ' .. q(lsreg) .. ' ] && ' .. q(lsreg) .. ' -f "$DST" 2>/dev/null || true',
                'command -v mdimport >/dev/null 2>&1 && mdimport "$DST" 2>/dev/null || true',
            }, "\n")
            assert(os.execute(script) == true or os.execute(script) == 0)
            return
        end
        -- No .app bundle (a bare-binary macOS tool): fall back to a shim .app.
        local appdir = appsdir .. "/" .. display .. ".app"
        local plist = table.concat({
            '<?xml version="1.0" encoding="UTF-8"?>',
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
            '<plist version="1.0"><dict>',
            '<key>CFBundleName</key><string>' .. display .. '</string>',
            '<key>CFBundleDisplayName</key><string>' .. display .. '</string>',
            '<key>CFBundleIdentifier</key><string>' .. (L.bundle_id or ("local.toolbox." .. tool)) .. '</string>',
            '<key>CFBundleExecutable</key><string>' .. tool .. '</string>',
            '<key>CFBundlePackageType</key><string>APPL</string>',
            (p.icon and '<key>CFBundleIconFile</key><string>icon.icns</string>' or ''),
            '</dict></plist>',
        }, "\n")
        local script = table.concat({
            "set -e",
            "AD=" .. q(appdir),
            'mkdir -p "$AD/Contents/MacOS" "$AD/Contents/Resources"',
            "printf %s " .. q(plist) .. ' > "$AD/Contents/Info.plist"',
            "printf '#!/bin/sh\\nexec %s \"$@\"\\n' " .. q(exec) .. ' > "$AD/Contents/MacOS/' .. tool .. '"',
            'chmod +x "$AD/Contents/MacOS/' .. tool .. '"',
            (p.icon and ('cp ' .. q(dest .. "/Menu/" .. tool .. ".icns") .. ' "$AD/Contents/Resources/icon.icns" 2>/dev/null || true') or ""),
        }, "\n")
        assert(os.execute(script) == true or os.execute(script) == 0)
    else
        local appsdir = os.getenv("MISE_APP_LAUNCHER_DIR") or (os.getenv("HOME") .. "/.local/share/applications")
        local icon = dest .. "/Menu/" .. tool .. ".png"
        local desktop = table.concat({
            "[Desktop Entry]",
            "Type=Application",
            "Name=" .. display,
            "Comment=" .. (L.description or display),
            "Exec=" .. exec,
            "Icon=" .. icon,
            "Terminal=false",
            "Categories=" .. (L.categories or "Utility;"),
            L.wm_class and ("StartupWMClass=" .. L.wm_class) or "",
        }, "\n")
        local script = table.concat({
            "set -e",
            "DIR=" .. q(appsdir),
            'mkdir -p "$DIR"',
            "printf %s " .. q(desktop .. "\n") .. ' > "$DIR/' .. tool .. '.desktop"',
        }, "\n")
        assert(os.execute(script) == true or os.execute(script) == 0)
    end
end
