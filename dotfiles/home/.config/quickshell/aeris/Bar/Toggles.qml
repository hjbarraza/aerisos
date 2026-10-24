import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Recording, night light, Do Not Disturb, Stay Awake. Each command pushes a bar refresh
// when it changes state; the 60 s interval only catches changes made elsewhere.
RowLayout {
    spacing: 0
    StatusModule { cmd: ["sh", "-c", "~/.local/bin/screenrecord status"]; interval: 60000
        onClick: () => Shell.sh("~/.local/bin/screenrecord") }
    StatusModule { cmd: ["sh", "-c", "~/.local/bin/nightlight"]; interval: 60000
        onClick: () => Shell.sh("~/.local/bin/nightlight toggle") }
    StatusModule { cmd: ["sh", "-c", "~/.local/bin/dnd"]; interval: 60000
        onClick: () => Shell.sh("~/.local/bin/dnd toggle") }
    StatusModule { cmd: ["sh", "-c", "~/.local/bin/stay-awake"]; interval: 60000
        onClick: () => Shell.sh("~/.local/bin/stay-awake toggle") }
}
