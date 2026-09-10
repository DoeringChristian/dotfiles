"""Kitty kitten: context-aware window launch.

When the active window is an sshr remote session, launches a new sshr
window to the same host in the same working directory. Otherwise falls
back to launching a local window with cwd=current.
"""

import os
import shutil
from urllib.parse import unquote, urlparse

# kitty inherits the desktop session's PATH, which need not match the shell's:
# on Linux it often lacks the Homebrew prefix while still carrying an older
# sshr (e.g. a leftover nix profile), so a bare "sshr" would start the wrong
# binary. Resolve the Homebrew one first, then fall back to PATH.
_BREW_BINS = (
    "/opt/homebrew/bin",
    "/home/linuxbrew/.linuxbrew/bin",
    os.path.expanduser("~/.homebrew/bin"),
)


def sshr_exe():
    for d in _BREW_BINS:
        exe = os.path.join(d, "sshr")
        if os.access(exe, os.X_OK):
            return exe
    return shutil.which("sshr") or "sshr"


def main(args):
    pass


from kittens.tui.handler import result_handler


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    tab = boss.active_tab
    if tab is None:
        return

    sshr_host = window.user_vars.get("sshr_host", "")

    if sshr_host:
        remote_cwd = ""
        osc7_url = window.screen.last_reported_cwd
        if osc7_url:
            url = osc7_url.decode() if isinstance(osc7_url, bytes) else osc7_url
            # sshr percent-encodes the path in the OSC 7 URL so spaces, '#', and
            # '?' survive; decode it back before handing it to --remote-cwd.
            remote_cwd = unquote(urlparse(url).path)

        cmd = [sshr_exe()]
        if remote_cwd:
            cmd.extend(["--remote-cwd", remote_cwd])
        cmd.append(sshr_host)
        tab.new_window(cmd=cmd)
    else:
        cwd = window.cwd_of_child
        if cwd:
            tab.new_window(cwd=cwd)
        else:
            tab.new_window()
