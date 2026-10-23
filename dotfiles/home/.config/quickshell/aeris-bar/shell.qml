// AerisOS top bar — quickshell 0.3.x. Replaces waybar.
// Hide/show:   qs ipc -p ~/.config/quickshell/aeris-bar/shell.qml call bar toggle
// Refresh now: qs ipc -p ~/.config/quickshell/aeris-bar/shell.qml call bar refresh
//@ pragma IconTheme Mono
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Widgets

ShellRoot {
    id: root
    readonly property color bg:   "#0a0a0a"
    readonly property color fg:   "#e6e6e6"
    readonly property color dim:  "#7a7a7a"
    readonly property color warn: "#ffffff"
    readonly property string sans: "Söhne"
    readonly property string nerd: "NotoSansM Nerd Font"
    property bool shown: true
    property int refreshTick: 0        // bumped by IPC; StatusModules re-run on change

    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
        function refresh(): void { root.refreshTick++ }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }

    // A waybar-style custom module: runs `cmd`, expects {text, class, tooltip} JSON.
    // Re-runs every `interval` ms (0 = only on refreshTick) and on refreshTick.
    component StatusModule: Text {
        id: mod
        property list<string> cmd
        property int interval: 0
        property var onClick: null
        property var onRightClick: null
        property string klass: ""
        color: (klass === "off" || klass === "disconnected") ? root.dim : root.fg
        font.family: root.nerd
        font.pixelSize: 12
        visible: text !== ""
        leftPadding: visible ? 7 : 0
        rightPadding: visible ? 8 : 0

        property int _tick: root.refreshTick
        on_TickChanged: proc.running = true
        Process {
            id: proc
            command: mod.cmd
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const j = JSON.parse(text.trim() || "{}")
                        mod.text = j.text ?? ""
                        mod.klass = j.class ?? ""   // "off" renders dim (e.g. Stay Awake)
                    } catch (e) { mod.text = "" }
                }
            }
        }
        Timer {
            interval: mod.interval; running: mod.interval > 0; repeat: true
            onTriggered: proc.running = true
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: ev => {
                const f = ev.button === Qt.RightButton ? mod.onRightClick : mod.onClick
                if (f) { f(); Qt.callLater(() => proc.running = true) }
            }
        }
    }

    function sh(c) { Quickshell.execDetached(["sh", "-c", c]) }

    PanelWindow {
        id: bar
        visible: root.shown
        anchors { top: true; left: true; right: true }
        implicitHeight: 26
        color: root.bg
        WlrLayershell.layer: WlrLayer.Top

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16
            spacing: 0

            // ---- left: Æ mark + workspaces -------------------------------
            Text {
                text: "Æ"
                color: "#ffffff"
                font { family: root.sans; weight: Font.Bold; pixelSize: 15 }
                rightPadding: 10
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sh("~/.local/bin/aeris-menu")
                }
            }
            Repeater {   // persistent 1–5
                model: 5
                Text {
                    required property int index
                    readonly property int ws: index + 1
                    readonly property bool focused: (Hyprland.focusedWorkspace?.id ?? 1) === ws
                    readonly property bool exists: Hyprland.workspaces.values.some(w => w.id === ws)
                    text: focused ? "󱓻" : String(ws)
                    color: focused ? "#ffffff" : (exists ? root.fg : root.dim)
                    font { family: focused ? root.nerd : root.sans; pixelSize: 12 }
                    leftPadding: 6; rightPadding: 6
                    MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + parent.ws) }
                }
            }
            Repeater {   // any extra workspaces beyond 5
                model: ScriptModel { values: Hyprland.workspaces.values.filter(w => w.id > 5) }
                Text {
                    required property var modelData
                    readonly property bool focused: Hyprland.focusedWorkspace?.id === modelData.id
                    text: focused ? "󱓻" : String(modelData.id % 10)
                    color: focused ? "#ffffff" : root.fg
                    font { family: focused ? root.nerd : root.sans; pixelSize: 12 }
                    leftPadding: 6; rightPadding: 6
                    MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + parent.modelData.id) }
                }
            }

            Item { Layout.fillWidth: true }

            // ---- center: toggles + clock ---------------------------------
            StatusModule { cmd: ["sh", "-c", "~/.local/bin/screenrecord status"]; interval: 10000
                onClick: () => root.sh("~/.local/bin/screenrecord") }
            StatusModule { cmd: ["sh", "-c", "~/.local/bin/nightlight"]; interval: 10000
                onClick: () => root.sh("~/.local/bin/nightlight toggle") }
            StatusModule { cmd: ["sh", "-c", "~/.local/bin/dnd"]; interval: 10000
                onClick: () => root.sh("~/.local/bin/dnd toggle") }
            StatusModule { cmd: ["sh", "-c", "~/.local/bin/stay-awake"]; interval: 10000
                onClick: () => root.sh("~/.local/bin/stay-awake toggle") }
            Text {
                property bool alt: false
                text: alt ? Qt.formatDateTime(clock.date, "dd MMMM") + "  W" + root.isoWeek(clock.date) + " " + Qt.formatDateTime(clock.date, "yyyy")
                          : Qt.formatDateTime(clock.date, "dddd HH:mm")
                color: root.fg
                font { family: root.sans; pixelSize: 12 }
                leftPadding: 7
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: parent.alt = !parent.alt
                }
            }
            Text {   // voxtype, streaming — centred, right of the clock
                id: vox
                property string state: "stopped"
                readonly property var icons: ({ idle: "\u{F036C}", recording: "\u{F036C}", transcribing: "\u{F036C}…", stopped: "\u{F036D}" })
                text: icons[state] ?? ""
                color: state === "recording" ? root.warn
                     : state === "transcribing" ? root.fg : root.dim
                font { family: root.nerd; pixelSize: 12 }
                leftPadding: 7; rightPadding: 8
                Process {
                    command: ["voxtype", "status", "--follow", "--format", "json"]
                    running: true
                    stdout: SplitParser {
                        onRead: line => {
                            try { vox.state = JSON.parse(line).alt ?? "stopped" } catch (e) {}
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: ev => ev.button === Qt.RightButton
                        ? root.sh("systemctl --user restart voxtype")
                        : root.sh("ghostty -e voxtype configure")
                }
            }

            // ---- AERIS alerts pill + watchlist, from status.json (inotify, no polling)
            Item {
                id: aeris
                property var d: ({})
                property int tick: 0   // re-checks staleness once a minute
                visible: false; width: 0; height: 0
                Timer { interval: 60000; running: true; repeat: true; onTriggered: aeris.tick++ }
                FileView {
                    path: "/var/lib/aeris/status.json"
                    watchChanges: true
                    onFileChanged: this.reload()
                    onLoaded: parse()
                    onTextChanged: parse()
                    function parse() { try { aeris.d = JSON.parse(this.text()) } catch (e) { aeris.d = ({}) } }
                    Component.onCompleted: parse()
                }
                // Airspace events (jamming, squawk, ISS/CSS overhead) have their own pill; these
                // alerts stay out of the general one
                readonly property var airAlerts: ["air.gnss", "air.emergency", "space.iss", "space.css"]
                readonly property var airHot: {
                    const out = []
                    for (const a of d.alerts || []) {
                        if (a === "air.gnss") out.push("GNSS " + String(d.air?.gnss ?? "JAMMED").split(" ")[0])
                        else if (a === "air.emergency") out.push("SQUAWK " + String(d.air?.emergency ?? "").split(" ")[0])
                        else if (a === "space.iss") out.push("ISS OVERHEAD")
                        else if (a === "space.css") out.push("CSS OVERHEAD")
                    }
                    return out
                }
                // Bright satellites above 10 degrees right now ("5 O/H · ARIANE 40 R/B")
                readonly property int airSats: parseInt(/^\s*(\d+)\s*O\/H/.exec(String(d.space?.sats ?? ""))?.[1] ?? "0")
                readonly property var airLabels: airHot.concat(airSats > 0 ? [airSats + " SAT" + (airSats === 1 ? "" : "S") + " O/H"] : [])
                // One short label per remaining status.json alert
                readonly property var labels: {
                    const out = []
                    for (const a of d.alerts || []) {
                        if (airAlerts.includes(a)) continue
                        else if (a === "space.scales") out.push((/G\d/.exec(String(d.space?.scales ?? ""))?.[0] ?? "G?") + " STORM")
                        else if (a === "world.outages") out.push("NET OUTAGE " + (String(d.net?.city ?? "").split(", ").pop() ?? ""))
                        else out.push(a.toUpperCase())
                    }
                    return out
                }
                readonly property int watchNew:
                    (d.watch?.items ?? []).reduce((n, i) => n + (i.new?.length ?? 0), 0)
                // Reading counts: after an ack the counter drops to 0 at once and stays
                // there until the collector's next run moves the real number
                property int ackedAt: -1
                readonly property int watchShown: watchNew === ackedAt ? 0 : watchNew
                // Collector writes every minute; much older than 10 min means it is down
                readonly property bool stale: {
                    tick
                    const m = /^(\d\d):(\d\d)$/.exec(d.updated ?? "")
                    if (!m) return true
                    const now = new Date()
                    return ((now.getHours() * 60 + now.getMinutes()
                             - parseInt(m[1]) * 60 - parseInt(m[2])) + 1440) % 1440 > 10
                }
            }
            Rectangle {   // alerts read inverted, as on the lock and login screens
                visible: aeris.labels.length > 0
                color: "#ffffff"; radius: 3
                implicitWidth: alertText.implicitWidth + 12
                implicitHeight: 16
                Text {
                    id: alertText
                    anchors.centerIn: parent
                    text: aeris.labels.join(" · ")
                    color: "#000000"
                    font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                }
                MouseArea {   // left: orbit popup (map + readouts); right: plain-text alert list
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: ev => root.sh(ev.button === Qt.RightButton
                        ? "ghostty --class=aeris.tui-float -e ~/.local/bin/aeris-alerts"
                        : "~/.local/bin/aeris-orbit")
                }
            }
            Rectangle {   // airspace: inverted for notable events, outlined when only satellites are up
                readonly property bool hot: aeris.airHot.length > 0
                visible: aeris.airLabels.length > 0
                color: hot ? "#ffffff" : "transparent"; radius: 3
                border { width: hot ? 0 : 1; color: root.fg }
                implicitWidth: airText.implicitWidth + 12
                implicitHeight: 16
                Text {
                    id: airText
                    anchors.centerIn: parent
                    text: aeris.airLabels.join(" · ")
                    color: parent.hot ? "#000000" : root.fg
                    font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                }
                MouseArea {   // left: orbit popup (map + readouts); right: plain-text alert list
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: ev => root.sh(ev.button === Qt.RightButton
                        ? "ghostty --class=aeris.tui-float -e ~/.local/bin/aeris-alerts"
                        : "~/.local/bin/aeris-orbit")
                }
            }
            Text {   // the collector stopped writing: everything above is old
                visible: aeris.stale
                text: "STALE"
                color: root.dim
                font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                leftPadding: 7; rightPadding: 8
            }

            Item { Layout.fillWidth: true }

            // ---- right: tailscale, net, audio, battery, drawer -----------
            StatusModule { id: tsIcon; cmd: ["sh", "-c", "~/.local/bin/tailscale-status"]; interval: 10000
                onClick: () => tsPopup.toggle()
                onRightClick: () => root.sh("~/.local/bin/tailscale-status admin") }
            Text {   // network: type + wifi signal tiers, like waybar
                id: net
                property string icon: "󰤮"
                text: icon
                color: icon === "󰤮" ? root.dim : root.fg
                font { family: root.nerd; pixelSize: 12 }
                leftPadding: 7; rightPadding: 8
                Process {
                    id: netProc
                    command: ["sh", "-c",
                        "t=$(nmcli -t -f TYPE,STATE device | grep ':connected' | cut -d: -f1 | head -1); " +
                        "if [ \"$t\" = wifi ]; then s=$(nmcli -t -f ACTIVE,SIGNAL device wifi | grep '^yes' | cut -d: -f2 | head -1); echo wifi ${s:-0}; " +
                        "elif [ -n \"$t\" ]; then echo ethernet; else echo none; fi"]
                    running: true
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const p = text.trim().split(" ")
                            if (p[0] === "ethernet") net.icon = "󰀂"
                            else if (p[0] === "wifi") {
                                const s = parseInt(p[1] ?? "0")
                                net.icon = s > 75 ? "󰤨" : s > 50 ? "󰤥" : s > 25 ? "󰤢" : "󰤟"
                            } else net.icon = "󰤮"
                        }
                    }
                }
                Timer { interval: 3000; running: true; repeat: true; onTriggered: netProc.running = true }
                MouseArea { anchors.fill: parent; onClicked: root.sh("ghostty --class=aeris.tui-float -e nmtui") }
            }
            Text {   // volume, live via PipeWire
                readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
                readonly property real vol: audio?.volume ?? 0
                readonly property bool muted: audio?.muted ?? true
                text: muted ? "󰝟" : vol < 0.34 ? "󰕿" : vol < 0.67 ? "󰖀" : "󰕾"
                color: muted ? root.dim : root.fg
                font { family: root.nerd; pixelSize: 12 }
                leftPadding: 7; rightPadding: 8
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: ev => {
                        if (ev.button === Qt.RightButton) root.sh("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
                        else if (ev.button === Qt.MiddleButton) root.sh("pavucontrol")
                        else root.sh("ghostty --class=aeris.tui-float -e wiremix")
                    }
                    onWheel: w => root.sh("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%" + (w.angleDelta.y > 0 ? "+" : "-"))
                }
            }
            Text {   // battery via UPower
                readonly property var dev: UPower.displayDevice
                readonly property real pct: (dev?.percentage ?? 0) * 100
                readonly property bool charging: dev != null &&
                    (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                readonly property var icons: ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"]
                readonly property var cicons: ["󰢜","󰂆","󰂇","󰂈","󰢝","󰂉","󰢞","󰂊","󰂋","󰂅"]
                readonly property int idx: Math.max(0, Math.min(9, Math.floor(pct / 10)))
                property bool showPct: false   // click toggles the % readout
                visible: dev?.isLaptopBattery ?? false
                text: (charging ? cicons[idx] : icons[idx])
                    + (showPct || (pct <= 20 && !charging) ? " " + Math.round(pct) + "%" : "")
                color: pct <= 20 && !charging ? root.warn : root.fg
                font { family: root.nerd; pixelSize: 12 }
                leftPadding: 7; rightPadding: 8
                MouseArea { anchors.fill: parent; onClicked: parent.showPct = !parent.showPct }
            }

            // ---- tray drawer: 󰅁 expands tray + bt + backlight + cpu + power
            Text {
                id: expander
                property bool open: false
                text: open ? "󰅂" : "󰅁"
                color: root.dim
                font { family: root.nerd; pixelSize: 12 }
                leftPadding: 4; rightPadding: 6
                MouseArea { anchors.fill: parent; onClicked: expander.open = !expander.open }
            }
            RowLayout {
                spacing: 0
                visible: expander.open
                Repeater {   // system tray
                    model: SystemTray.items
                    Item {
                        id: trayItem
                        required property var modelData
                        implicitWidth: 24; implicitHeight: 16
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 12
                            source: trayItem.modelData.icon
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: ev => {
                                // menu-only items have no activate action: ones that say so
                                // (LocalSend) and ayatana items that only carry a menu (nm-applet)
                                const menuOnly = trayItem.modelData.onlyMenu ||
                                                 trayItem.modelData.id === "nm-applet"
                                if (trayItem.modelData.hasMenu &&
                                    (ev.button === Qt.RightButton || menuOnly))
                                    menuAnchor.open()
                                else trayItem.modelData.activate()
                            }
                        }
                        QsMenuAnchor {
                            id: menuAnchor
                            menu: trayItem.modelData.menu
                            anchor.window: bar
                            anchor.rect.x: trayItem.mapToItem(null, 0, 0).x
                            anchor.rect.y: bar.implicitHeight
                        }
                    }
                }
                StatusModule {   // bluetooth
                    cmd: ["sh", "-c",
                        "if ! bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then echo '{\"text\":\"󰂲\"}'; " +
                        "elif [ \"$(bluetoothctl devices Connected 2>/dev/null | wc -l)\" -gt 0 ]; then echo '{\"text\":\"󰂱\"}'; " +
                        "else echo '{\"text\":\"󰂯\"}'; fi"]
                    interval: 10000
                    onClick: () => root.sh("ghostty --class=aeris.tui-float -e bluetui")
                }
                Text {   // backlight
                    id: backlight
                    property int pct: -1
                    visible: pct >= 0
                    text: pct > 66 ? "󰃠" : pct > 33 ? "󰃟" : "󰃞"
                    color: root.fg
                    font { family: root.nerd; pixelSize: 12 }
                    leftPadding: 7; rightPadding: 8
                    Process {
                        id: blProc
                        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d %"]
                        running: true
                        stdout: StdioCollector {
                            onStreamFinished: backlight.pct = text.trim() === "" ? -1 : parseInt(text.trim())
                        }
                    }
                    Timer { interval: 5000; running: expander.open; repeat: true; onTriggered: blProc.running = true }
                    MouseArea {
                        anchors.fill: parent
                        onWheel: w => {
                            root.sh("brightnessctl -e4 -n2 set 5%" + (w.angleDelta.y > 0 ? "+" : "-"))
                            Qt.callLater(() => blProc.running = true)
                        }
                    }
                }
                Text {   // cpu
                    text: "󰍛"
                    color: root.fg
                    font { family: root.nerd; pixelSize: 12 }
                    leftPadding: 7; rightPadding: 8
                    MouseArea { anchors.fill: parent; onClicked: root.sh("command -v btop >/dev/null && ghostty -e btop || ghostty -e top") }
                }
                StatusModule {   // power profile; click cycles
                    cmd: ["sh", "-c",
                        "p=$(powerprofilesctl get 2>/dev/null); case $p in performance) echo '{\"text\":\"\"}';; " +
                        "power-saver) echo '{\"text\":\"\"}';; balanced) echo '{\"text\":\"\"}';; *) echo '{\"text\":\"\"}';; esac"]
                    interval: 10000
                    onClick: () => root.sh(
                        "p=$(powerprofilesctl get); case $p in balanced) n=performance;; performance) n=power-saver;; *) n=balanced;; esac; powerprofilesctl set $n")
                }
            }
        }
    }

    // Tailscale submenu: click the bar icon. Devices with online dots (click a row to
    // copy its IP), connect/disconnect, admin console. Monochrome like the rest of the
    // bar; reads `tailscale status --json` directly (the user is the tailscale operator).
    PopupWindow {
        id: tsPopup
        property string backend: ""
        property var rows: []
        property string copied: ""
        anchor.window: bar
        // mapToItem has no change signal, so a plain binding goes stale (menu far left):
        // position is computed when the menu opens.
        anchor.rect.x: 0
        anchor.rect.y: bar.implicitHeight
        implicitWidth: 252
        implicitHeight: tsCol.implicitHeight + 20
        visible: false
        color: "transparent"
        function toggle() {
            if (visible) visible = false
            else {
                anchor.rect.x = tsIcon.mapToItem(null, 0, 0).x + tsIcon.width - implicitWidth
                tsProc.running = true; visible = true
            }
        }
        function act(c) { root.sh(c); actTimer.restart() }
        Timer { id: actTimer; interval: 800; onTriggered: { tsProc.running = true; root.refreshTick++ } }
        Timer { id: copyTimer; interval: 1500; onTriggered: tsPopup.copied = "" }
        Process {
            id: tsProc
            command: ["tailscale", "status", "--json"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const j = JSON.parse(text)
                        tsPopup.backend = j.BackendState ?? ""
                        const mk = (p, self) => ({
                            // iOS devices report HostName "localhost": use the DNS name
                            host: (!p.HostName || p.HostName === "localhost")
                                  ? (p.DNSName ?? "?").split(".")[0] : p.HostName,
                            ip: (p.TailscaleIPs ?? [""])[0] ?? "",
                            online: self ? true : p.Online === true,
                            self: self })
                        const peers = Object.values(j.Peer ?? {}).map(p => mk(p, false))
                        peers.sort((a, b) => (b.online - a.online) || a.host.localeCompare(b.host))
                        tsPopup.rows = (j.Self ? [mk(j.Self, true)] : []).concat(peers)
                    } catch (e) { tsPopup.backend = "Off"; tsPopup.rows = [] }
                }
            }
        }
        HyprlandFocusGrab { windows: [tsPopup]; active: tsPopup.visible; onCleared: tsPopup.visible = false }
        Rectangle { anchors.fill: parent; color: root.bg; border.color: "#2a2a2a"; border.width: 1 }
        Column {
            id: tsCol
            x: 12; y: 10
            width: tsPopup.implicitWidth - 24
            spacing: 3
            RowLayout {
                width: parent.width
                Text { text: "TAILSCALE"; color: root.fg; font { family: root.sans; pixelSize: 11; letterSpacing: 1 } }
                Item { Layout.fillWidth: true }
                Text {
                    text: tsPopup.backend === "Running" ? "CONNECTED"
                        : tsPopup.backend === "Stopped" ? "DISCONNECTED"
                        : tsPopup.backend === "NeedsLogin" ? "NEEDS LOGIN" : tsPopup.backend.toUpperCase()
                    color: tsPopup.backend === "Running" ? root.fg : root.dim
                    font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                }
            }
            Item { width: 1; height: 3 }
            Repeater {
                model: tsPopup.rows
                RowLayout {
                    id: tsRow
                    required property var modelData
                    width: tsCol.width
                    spacing: 6
                    Text { text: tsRow.modelData.online ? "●" : "○"
                        color: tsRow.modelData.online ? root.fg : root.dim
                        font.pixelSize: 8 }
                    Text {
                        text: tsRow.modelData.host + (tsRow.modelData.self ? " · this" : "")
                        color: tsRow.modelData.online ? root.fg : root.dim
                        font { family: root.sans; pixelSize: 12 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: tsPopup.copied === tsRow.modelData.ip ? "copied" : tsRow.modelData.ip
                        color: root.dim
                        font { family: root.sans; pixelSize: 11 }
                    }
                    // Click anywhere on the row to copy the device's Tailscale IP
                    TapHandler {
                        onTapped: {
                            root.sh("wl-copy " + tsRow.modelData.ip)
                            tsPopup.copied = tsRow.modelData.ip
                            copyTimer.restart()
                        }
                    }
                }
            }
            Item { width: 1; height: 4 }
            Rectangle { width: parent.width; height: 1; color: "#2a2a2a" }
            Item { width: 1; height: 2 }
            RowLayout {
                width: parent.width
                Text {
                    text: tsPopup.backend === "Running" ? "DISCONNECT" : "CONNECT"
                    color: root.fg
                    font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                    TapHandler { onTapped: tsPopup.act(tsPopup.backend === "Running" ? "tailscale down" : "tailscale up") }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "ADMIN ↗"
                    color: root.dim
                    font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                    TapHandler { onTapped: { tsPopup.visible = false; root.sh("~/.local/bin/tailscale-status admin") } }
                }
            }
        }
    }

    function isoWeek(d) {
        const t = new Date(d.getTime())
        t.setHours(0, 0, 0, 0)
        t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7))
        const w1 = new Date(t.getFullYear(), 0, 4)
        return 1 + Math.round(((t - w1) / 86400000 - 3 + ((w1.getDay() + 6) % 7)) / 7)
    }
}
