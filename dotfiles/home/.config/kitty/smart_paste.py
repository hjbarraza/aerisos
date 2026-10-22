# Ctrl+V: paste text from the clipboard as usual, but if the clipboard holds
# only an image (e.g. a screenshot), forward Ctrl+V to the running program so
# apps like Claude Code can read the image themselves.
import subprocess

from kittens.tui.handler import result_handler

TEXT_TYPES = ("UTF8_STRING", "STRING", "TEXT")


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    try:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True,
                               text=True, timeout=1).stdout.split()
    except Exception:
        types = []
    if any(t.startswith("text/") or t in TEXT_TYPES for t in types):
        boss.paste_from_clipboard()   # pastes into the active window (the one Ctrl+V was pressed in)
    else:
        window.send_key("ctrl+v")
