"""
Kitten for opening a new window. If the current window is a persistent
SSH session, opens a new persistent-ssh connection to the same host.
Otherwise, opens a regular local window in the current directory.
"""


def main(args):
    pass


def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    user_vars = getattr(window, 'user_vars', {})
    host = user_vars.get('persistent_ssh_host')

    if host:
        remote_shell = user_vars.get('persistent_ssh_shell', 'bash')
        boss.call_remote_control(window, (
            'launch',
            '--type=window',
            'persistent-ssh', '--new', '--shell', remote_shell, host,
        ))
    else:
        boss.call_remote_control(window, (
            'launch',
            '--type=window',
            '--cwd=current',
        ))


handle_result.no_ui = True
