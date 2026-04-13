"""
Kitten for intentionally closing a window. Sets a user variable so the
persistent SSH watcher knows this was deliberate (and should kill the
remote shpool session) rather than a connection drop.

For non-SSH windows, this behaves identically to close_window.
"""


def main(args):
    pass


def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    user_vars = getattr(window, 'user_vars', {})
    if user_vars.get('persistent_ssh_host'):
        boss.call_remote_control(window, (
            'set-user-vars',
            f'--match=id:{target_window_id}',
            'persistent_ssh_closing=1',
        ))

    boss.call_remote_control(window, (
        'close-window',
        f'--match=id:{target_window_id}',
    ))


handle_result.no_ui = True
