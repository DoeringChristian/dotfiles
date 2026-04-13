"""
Kitty watcher for persistent SSH sessions.

Detects when an SSH window closes (connection drop) and auto-reconnects
by relaunching the same kitten ssh command. The remote shell survives
because it runs inside a shpool session.

Intentional closes (user pressing the close keybinding) are distinguished
from connection drops via the 'persistent_ssh_closing' user variable.
"""

import subprocess
import threading


def on_close(boss, window, data):
    """Called when a window closes. Auto-reconnect SSH sessions."""
    user_vars = getattr(window, 'user_vars', {})

    host = user_vars.get('persistent_ssh_host')
    session_name = user_vars.get('persistent_ssh_session')

    if not host or not session_name:
        return  # Not a persistent SSH window

    remote_shell = user_vars.get('persistent_ssh_shell', 'bash')

    # Check if this was an intentional close
    if user_vars.get('persistent_ssh_closing') == '1':
        # User intentionally closed — kill the remote shpool session
        try:
            subprocess.Popen(
                ['ssh', host,
                 'export PATH=$HOME/.cargo/bin:$PATH;'
                 f' shpool kill {session_name}'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass
        return

    # Connection dropped — auto-reconnect after a short delay
    # to let the window teardown complete
    def _reconnect():
        try:
            boss.call_remote_control(None, (
                'launch',
                '--type=window',
                'persistent-ssh',
                '--shell', remote_shell,
                '--session', session_name,
                host,
            ))
        except Exception:
            pass

    threading.Timer(0.5, _reconnect).start()
