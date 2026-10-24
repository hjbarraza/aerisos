// AerisOS shell: one Quickshell process for the top bar and the pill dock.
//   aeris-shell bar toggle|refresh     aeris-shell dock reveal|conceal|flip
// Layout: Commons/ (Theme, Status, Shell singletons), Ui/ (shared components),
// Bar/ (the bar and its widgets), Dock/ (the pill dock with its hover autohide).
//@ pragma IconTheme Mono
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Bar"
import "Dock"

ShellRoot {
    IpcHandler {
        target: "bar"
        function toggle(): void { Shell.barShown = !Shell.barShown }
        function refresh(): void { Shell.refreshTick++ }
    }
    IpcHandler {
        target: "dock"
        // "show"/"hide" are reserved qs ipc subcommands, hence these names
        function reveal(): void { dock.hidden = false }
        function conceal(): void { dock.hidden = true }
        function flip(): void { dock.hidden = !dock.hidden }
    }

    Bar {}
    Dock { id: dock }
}
