# Smart right-click paste (bound in kitty.conf):
# - clipboard has text -> paste it like a normal paste
# - clipboard is image-only (e.g. a fresh screenshot) -> send ctrl+v to the
#   running app instead, so programs like Claude Code read the image themselves
import subprocess

from kittens.tui.handler import result_handler


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    try:
        types = subprocess.run(
            ["wl-paste", "--list-types"], capture_output=True, text=True, timeout=2
        ).stdout
    except Exception:
        types = "text/plain"  # on any failure fall back to a plain text paste
    if "text/" in types or "STRING" in types:
        boss.paste_from_clipboard()
    else:
        w.send_key("ctrl+v")
