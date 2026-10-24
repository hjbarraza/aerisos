import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Output volume, live from PipeWire. Click: mixer; right: mute; middle: pavucontrol; wheel: volume.
Glyph {
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }
    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property real vol: audio?.volume ?? 0
    readonly property bool muted: audio?.muted ?? true
    text: muted ? "󰝟" : vol < 0.34 ? "󰕿" : vol < 0.67 ? "󰖀" : "󰕾"
    color: muted ? Theme.dim : Theme.fg
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: ev => {
            if (ev.button === Qt.RightButton) Shell.sh("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
            else if (ev.button === Qt.MiddleButton) Shell.sh("pavucontrol")
            else Shell.sh("ghostty --class=aeris.tui-float -e wiremix")
        }
        onWheel: w => Shell.sh("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%" + (w.angleDelta.y > 0 ? "+" : "-"))
    }
}
