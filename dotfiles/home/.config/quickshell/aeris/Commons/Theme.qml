pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colors, fonts and sizes for the whole shell. The defaults are below; a file at
// ~/.config/aeris/shell.json overrides any key and is watched, so an edit applies at once:
//   { "version": 1, "colors": { "fg": "#ffffff" }, "fonts": { "size": 13 } }
Singleton {
    id: theme

    readonly property var defaults: ({
        colors: { bg: "#0a0a0a", fg: "#e6e6e6", dim: "#7a7a7a", warn: "#ffffff", line: "#2a2a2a" },
        fonts:  { sans: "Söhne", nerd: "NotoSansM Nerd Font", size: 12, small: 11 },
        bar:    { height: 26 },
        dock:   { enabled: true }
    })
    property var user: ({})

    function get(section, key) {
        const u = user[section]
        return (u && u[key] !== undefined) ? u[key] : defaults[section][key]
    }

    readonly property color bg:   get("colors", "bg")
    readonly property color fg:   get("colors", "fg")
    readonly property color dim:  get("colors", "dim")
    readonly property color warn: get("colors", "warn")
    readonly property color line: get("colors", "line")
    readonly property string sans: get("fonts", "sans")
    readonly property string nerd: get("fonts", "nerd")
    readonly property int size:  get("fonts", "size")
    readonly property int small: get("fonts", "small")
    readonly property int barHeight: get("bar", "height")
    readonly property bool dockEnabled: get("dock", "enabled")

    readonly property string configPath: Quickshell.env("HOME") + "/.config/aeris/shell.json"

    function parse(text) {
        try {
            const j = JSON.parse(text)
            user = (j && j.version === 1) ? j : ({})
        } catch (e) {
            console.warn("shell.json: not valid JSON, using defaults:", e)
            user = ({})
        }
    }

    FileView {
        path: theme.configPath
        watchChanges: true
        printErrors: false
        onLoaded: theme.parse(text())
        onFileChanged: reload()
        onLoadFailed: theme.user = ({})
    }
}
