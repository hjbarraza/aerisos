#!/usr/bin/env python3
"""Window finder: list open windows in wofi and focus the one selected."""
import json
import subprocess

clients = json.loads(subprocess.check_output(["hyprctl", "-j", "clients"]))
# One line per window; the index keeps lines unique when titles repeat.
lines = {
    f"{i + 1}  {c['class']}: {c['title']}  [workspace {c['workspace']['name']}]": c["address"]
    for i, c in enumerate(clients)
}
choice = subprocess.run(
    ["wofi", "--dmenu", "--insensitive", "--prompt", "Window"],
    input="\n".join(lines), text=True, capture_output=True,
).stdout.strip()
if choice in lines:
    subprocess.run(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{lines[choice]}" }})'])
