# Smart paste, bound in kitty.conf to Ctrl+V and to right-click:
# - in vim/nvim, Ctrl+V keeps its own meaning (visual block), so the key goes straight through
# - clipboard has text -> paste it like a normal paste
# - clipboard is image-only (e.g. a fresh screenshot) -> send ctrl+v to the running app, so
#   programs like Claude Code read the image themselves; a bare shell can't take an image,
#   so there it does nothing (instead of the shell's ctrl+v "quoted insert")
import os
import subprocess

from kittens.tui.handler import result_handler

KEEP_CTRL_V = {"vim", "nvim", "vi", "view", "nano", "emacs"}
SHELLS = {"bash", "zsh", "fish", "sh", "dash"}


def main(args):
    pass


def foreground(w):
    try:
        cmd = w.child.foreground_cmdline
        return os.path.basename(cmd[0]).lstrip("-") if cmd else ""
    except Exception:
        return ""


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    fg = foreground(w)
    from_key = len(args) > 1 and args[1] == "key"
    if from_key and fg in KEEP_CTRL_V:
        w.send_key("ctrl+v")
        return
    try:
        types = subprocess.run(
            ["wl-paste", "--list-types"], capture_output=True, text=True, timeout=2
        ).stdout
    except Exception:
        types = "text/plain"  # on any failure fall back to a plain text paste
    if "text/" in types or "STRING" in types:
        boss.paste_from_clipboard()
    elif "image/" in types and fg not in SHELLS:
        w.send_key("ctrl+v")
