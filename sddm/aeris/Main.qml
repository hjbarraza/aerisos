// AerisOS login screen.
//
// A Swiss grid in a 1600x900 design space, scaled to fill the screen; fades in from black.
// Same layout as the lock screen (lock/make-hyprlock), so both screens line up.
//
// Columns: 12 on a 120 step from x=96 (88 wide, 32 gutters), so column n starts at
// 96 + 120(n-1) and the grid ends at 1504. Feeds take columns 1-9 (96-1144), the login and
// cards columns 10-12 (1176-1504). Baselines: every text row sits on the 18 px line grid
// 9 + 18n, from the top row at 99 to the bottom row at 819.
//
//   top row 99        date and time over the panel
//   wordmark 243      ÆRIS OS; the login's field rules sit on its baseline
//   tagline 297       and the login status beside it (empty until there is something to say)
//   rule 324          broken by the gutter between the two columns
//   heads 369 ...     WATCHLIST (grouped by topic, the topic on its group's first row) and
//                     WORLD as two-column tables (topic or outlet on column 1, telegram on
//                     column 3); beside them the cards from status.json `side` (aeris-status
//                     side_rows): an icon on column 10, its value 24 further; quiet values
//                     are left out, a stale card shows a warning glyph instead of a fetch
//                     time, one blank row between groups
//   bottom row 819    sleep · restart · power as icons
//
// IDENTITY, WEATHER, NETWORK and SECURITY are left out on purpose: the login screen is
// what people see when the laptop is left unattended. Alerts from status.json read inverted.
// Type: wordmark Söhne 144; everything else Söhne Mono, values 12 white, keys and labels 11
// grey; telegrams in sentence case, labels and readouts in capitals. Icons: Nerd Font glyphs
// (NotoSansM Nerd Font Mono, Material Design and Codicons), the code points aeris-status uses.

import QtQuick 2.15
import QtQuick.Window 2.15

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#000000"

    readonly property real s: Math.min(width / 1600, height / 900)
    readonly property color white: "#ffffff"
    readonly property color grey: "#7a7a7a"
    readonly property color read: "#c8c8c8"                 // acknowledged telegrams
    readonly property color dim: "#3a3a3a"
    readonly property color hairline: "#2a2a2a"
    readonly property string sans: config.Font || "Söhne"
    readonly property string mono: config.MonoFont || "Söhne Mono"
    readonly property string jp: config.JapaneseFont || "Source Han Sans JP"
    readonly property string icons: config.IconFont || "NotoSansM Nerd Font Mono"
    readonly property var glyph: ({ user: "\u{f0013}", key: "\u{f0dd6}", enter: "\u{f0054}",
                                    sleep: "\u{f0904}", restart: "\u{f0709}", power: "\u{f0425}",
                                    stale: "\u{ea6c}" })

    // ---- grid ----
    function col(n) { return 96 + 120 * (n - 1) }          // left edge of column n
    function colEnd(n) { return col(n) + 88 }               // right edge of column n
    readonly property real gridLeft: 96
    readonly property real gridRight: 1504
    readonly property real feedRight: 1144                 // end of column 9
    readonly property real panel: 1176                     // column 10
    readonly property real valueAt: 1200                   // values beside their icon on column 10
    readonly property real line: 18
    readonly property real topRow: 99
    readonly property real bottomRow: 819
    readonly property real markBy: 243                     // wordmark baseline
    readonly property real tagBy: 297                      // tagline / login status
    readonly property real ruleY: 324
    readonly property real sectionTop: 369                 // WATCHLIST head and first card head
    readonly property int watchRows: 8                     // as aeris-status WATCH_ROWS
    readonly property real worldHead: sectionTop + (watchRows + 2) * line   // 549
    readonly property int newsRows: 7                      // last row on 675, beside the last card row
    readonly property var feedCols: [col(1), col(3)]       // topic or outlet | telegram

    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string status: ""
    property bool busy: false

    // ---- live info (written by aeris-status.timer, re-read every 15 s) ----

    property var d: ({})
    function g(section, key) {
        const v = d[section] && d[section][key]
        return v ? String(v) : "—"
    }
    function loadStatus() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                try { root.d = JSON.parse(xhr.responseText) } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + (config.StatusFile || "/var/lib/aeris/status.json"))
        xhr.send()
    }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.loadStatus() }

    // The right column under the login, laid out by aeris-status (side_rows) as heads,
    // icon rows and blank rows, one per line from the first head down
    readonly property var side: d.side || []

    // Watchlist: status.json watch.rows ("* 12 NOV · TOPIC · telegram", grouped by topic,
    // the lines the lock screen splits the same way) as table cells: the topic only on its
    // group's first row, unread telegrams in white
    readonly property var watch: {
        const rows = ((d.watch && d.watch.rows) || []).slice(0, watchRows)
        let last = ""
        return rows.map(r => {
            const parts = r.slice(2).split(" · ")
            if (parts.length < 3)
                return { fresh: true, a: "", c: r.slice(2) }
            const cell = { fresh: r[0] === "*", a: parts[1] === last ? "" : parts[1], c: parts.slice(2).join(" · ") }
            last = parts[1]
            return cell
        })
    }
    readonly property string watchMore: d.watch && d.watch.more ? "+" + d.watch.more : ""
    readonly property bool watchStale: !!(d.watch && d.watch.stale)
    function stale(fresh) { return !fresh || /STALE|NO DATA/.test(fresh) }

    // World: the telegrams (world.telegrams) beside their item's time and outlet,
    // whole stories only, as many as fit
    readonly property var news: {
        const rows = []
        const items = (d.world && d.world.items) || []
        const tgs = (d.world && d.world.telegrams) || []
        for (let i = 0; i < tgs.length; i++) {
            const lines = tgs[i]
            if (rows.length + lines.length > newsRows)
                break
            const src = String((items[i] && items[i].source) || "").split(" · ")
            for (let j = 0; j < lines.length; j++)
                rows.push({ fresh: false,
                            a: j ? "" : src[0].replace(/\.(com|media|org|net|co\.uk)$/i, ""),
                            c: lines[j].replace(/^[·\s]+/, "") })
        }
        return rows
    }

    // ---- building blocks ----

    // Mono text positioned by baseline in design coordinates
    component Label: Text {
        property real bx: 0
        property real by: 0
        property bool alignRight: false
        font.family: root.mono
        font.pixelSize: 11 * root.s
        font.letterSpacing: 2 * root.s
        color: root.grey
        textFormat: Text.PlainText
        x: alignRight ? bx * root.s - width : bx * root.s
        y: by * root.s - baselineOffset
    }

    component Value: Label {
        font.pixelSize: 12 * root.s
        font.letterSpacing: 1.5 * root.s
        color: root.white
        elide: Text.ElideRight
    }

    component Action: Label {
        id: action
        signal activated()
        color: hover.containsMouse ? root.white : root.grey
        Behavior on color { ColorAnimation { duration: 150 } }
        MouseArea {
            id: hover
            anchors.fill: parent
            anchors.margins: -8 * root.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.activated()
        }
    }

    // An icon glyph, centred on a text row's baseline like a capital
    component Icon: Text {
        property real bx: 0
        property real by: 0
        property bool alignRight: false
        font.family: root.icons
        font.pixelSize: 18 * root.s
        color: root.grey
        textFormat: Text.PlainText
        x: alignRight ? bx * root.s - width : bx * root.s
        y: by * root.s - baselineOffset + 2 * root.s
    }

    // Section head: // and the name in white; on the right a note (how many more) and a
    // warning glyph when its data failed to refresh
    component Head: Item {
        property real bx: 0
        property real by: 0
        property real rightX: 0
        property string en: ""
        property string note: ""
        property bool stale: false
        Label { bx: parent.bx; by: parent.by; text: "//  " + parent.en; color: root.white }
        Icon { id: warn; visible: parent.stale; bx: parent.rightX; by: parent.by; alignRight: true; text: root.glyph.stale; color: root.white }
        Label { bx: parent.rightX - (parent.stale ? 22 : 0); by: parent.by; alignRight: true; text: parent.note }
    }

    // A feed table: topic or outlet | telegram, one row per line under the head
    component Feed: Item {
        property real by: 0
        property var rows: []
        Repeater {
            model: parent.rows
            delegate: Item {
                readonly property real ly: parent.by + (index + 1) * root.line
                Label { bx: root.feedCols[0]; by: ly; text: modelData.a }
                Value {
                    bx: root.feedCols[1]; by: ly
                    width: Math.min(implicitWidth, (root.feedRight - root.feedCols[1]) * root.s)
                    text: modelData.c
                    color: modelData.fresh ? root.white : root.read
                }
            }
        }
    }

    // A login row, laid out like a card row: icon on column 10, the typed value beside it
    // over an underline 7 below its baseline
    component Field: Item {
        property alias input: field
        property string icon: ""
        property real by: 0
        Icon { bx: root.panel; by: parent.by; text: parent.icon; color: field.activeFocus ? root.white : root.grey }
        TextInput {
            id: field
            x: root.valueAt * root.s
            y: parent.by * root.s - baselineOffset
            width: (root.gridRight - root.valueAt) * root.s
            font.family: root.mono
            font.pixelSize: 12 * root.s
            font.letterSpacing: 1.5 * root.s
            color: root.white
            selectionColor: root.grey
            clip: true
        }
        Rectangle {
            x: root.valueAt * root.s; y: (parent.by + 7) * root.s
            width: (root.gridRight - root.valueAt) * root.s
            height: Math.max(1, root.s)
            color: field.activeFocus ? root.white : root.dim
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Item {
        id: stage
        width: 1600 * root.s
        height: 900 * root.s
        anchors.centerIn: parent
        opacity: 0

        // ---- top row ----
        Label {
            id: dateLabel
            bx: root.panel; by: root.topRow
            color: root.white
        }
        Label {
            id: clockLabel
            bx: root.gridRight; by: root.topRow; alignRight: true
            color: root.white
            function update() {
                const now = new Date()
                dateLabel.text = Qt.formatDateTime(now, "ddd dd MMM yyyy").toUpperCase()
                text = Qt.formatTime(now, "HH:mm")
            }
            Component.onCompleted: update()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: clockLabel.update() }
        }

        // ---- wordmark (ÆRIS regular with the Æ ligature, OS bold), tagline, rule ----
        Repeater {
            model: [["ÆRIS", 94, Font.Normal], ["OS", 460, Font.Bold]]
            delegate: Text {
                text: modelData[0]
                font.family: root.sans
                font.weight: modelData[2]
                font.pixelSize: 144 * root.s
                font.letterSpacing: -6 * root.s
                color: root.white
                x: modelData[1] * root.s
                y: root.markBy * root.s - baselineOffset
            }
        }
        Label { bx: root.gridLeft; by: root.tagBy; font.pixelSize: 12 * root.s; color: root.white; text: "INTELLIGENCE OPERATING SYSTEM" }
        Text {
            text: "知能情報システム"
            font.family: root.jp
            font.pixelSize: 12 * root.s
            font.letterSpacing: 2 * root.s
            color: root.grey
            x: root.feedRight * root.s - width
            y: root.tagBy * root.s - baselineOffset
        }
        Rectangle { x: root.gridLeft * root.s; y: root.ruleY * root.s; width: (root.feedRight - root.gridLeft) * root.s; height: Math.max(1, root.s); color: root.white }
        Rectangle { x: root.panel * root.s; y: root.ruleY * root.s; width: (root.gridRight - root.panel) * root.s; height: Math.max(1, root.s); color: root.white }

        // ---- feeds and cards ----
        Item {
            id: info
            opacity: 0
            width: parent.width; height: parent.height

            Head { bx: root.gridLeft; by: root.sectionTop; rightX: root.feedRight; en: "WATCHLIST"; note: root.watchMore; stale: root.watchStale }
            Feed { by: root.sectionTop; rows: root.watch }
            Head { bx: root.gridLeft; by: root.worldHead; rightX: root.feedRight; en: "WORLD"; stale: root.stale(g("world", "fresh_news")) }
            Feed { by: root.worldHead; rows: root.news }

            Repeater {
                model: root.side
                delegate: Item {
                    readonly property real ly: root.sectionTop + index * root.line
                    readonly property var r: modelData
                    Head { visible: !!r.h; bx: root.panel; by: parent.ly; rightX: root.gridRight; en: r.h || ""; stale: !!r.stale }
                    Icon { visible: !!r.i; bx: root.panel; by: parent.ly; text: r.i || ""; color: r.a ? root.white : root.grey }
                    Value {
                        visible: !!r.i
                        bx: root.valueAt; by: parent.ly
                        width: Math.min(implicitWidth, (root.gridRight - root.valueAt) * root.s)
                        color: r.a ? "#000000" : root.white
                        text: r.v || ""
                        // Alerts read inverted: black on white
                        Rectangle {
                            z: -1
                            visible: !!r.a
                            anchors.fill: parent
                            anchors.leftMargin: -4 * root.s; anchors.rightMargin: -4 * root.s
                            color: root.white
                        }
                    }
                }
            }
        }

        // ---- login: the field rules on the wordmark's baseline, status on the tagline's ----
        Item {
            id: loginPanel
            opacity: 0
            x: 16 * root.s
            width: parent.width; height: parent.height

            Head { bx: root.panel; by: root.markBy - 3 * root.line; rightX: root.gridRight; en: "AUTHENTICATE" }
            Field {
                id: userField
                by: root.markBy - 2 * root.line
                icon: root.glyph.user
                input.text: userModel.lastUser
                input.KeyNavigation.tab: passField.input
                input.onAccepted: passField.input.forceActiveFocus()
            }
            Field {
                id: passField
                by: root.markBy
                icon: root.glyph.key
                input.echoMode: TextInput.Password
                input.passwordCharacter: "•"
                input.KeyNavigation.backtab: userField.input
                input.onAccepted: root.login()
            }
            Label {
                id: statusLabel
                bx: root.panel; by: root.tagBy
                text: [root.status, keyboard.capsLock ? "CAPS LOCK" : ""].filter(x => x).join(" · ")
                color: root.status === "ACCESS DENIED" ? root.white : root.grey
            }
            Action {
                bx: root.gridRight; by: root.tagBy; alignRight: true
                font.family: root.icons; font.pixelSize: 18 * root.s; font.letterSpacing: 0
                text: root.glyph.enter
                onActivated: root.login()
            }
        }

        // ---- bottom row: sleep, restart, power as icons (the session is always the last one used) ----
        Item {
            id: controls
            opacity: 0
            width: parent.width; height: parent.height

            Repeater {
                model: [[root.glyph.sleep, sddm.canSuspend, () => sddm.suspend()],
                        [root.glyph.restart, sddm.canReboot, () => sddm.reboot()],
                        [root.glyph.power, sddm.canPowerOff, () => sddm.powerOff()]]
                delegate: Action {
                    bx: root.gridRight - (2 - index) * 30; by: root.bottomRow; alignRight: true
                    font.family: root.icons; font.pixelSize: 18 * root.s; font.letterSpacing: 0
                    text: modelData[0]
                    visible: modelData[1]
                    onActivated: modelData[2]()
                }
            }
        }
    }

    function login() {
        if (root.busy || userField.input.text === "" || passField.input.text === "")
            return
        root.busy = true
        root.status = "AUTHENTICATING"
        sddm.login(userField.input.text, passField.input.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.status = "ACCESS DENIED"
            passField.input.text = ""
            passField.input.forceActiveFocus()
            denied.restart()
        }
        function onLoginSucceeded() {
            root.status = "ACCESS GRANTED"
        }
    }

    // Wrong password: status blinks three times
    SequentialAnimation {
        id: denied
        loops: 3
        PropertyAction { target: statusLabel; property: "opacity"; value: 0 }
        PauseAnimation { duration: 120 }
        PropertyAction { target: statusLabel; property: "opacity"; value: 1 }
        PauseAnimation { duration: 120 }
    }

    // Intro: fade in from black, then the login and information settle in
    SequentialAnimation {
        running: true
        PauseAnimation { duration: 150 }
        NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 700; easing.type: Easing.OutCubic }
        ParallelAnimation {
            NumberAnimation { target: loginPanel; property: "opacity"; to: 1; duration: 600; easing.type: Easing.OutCubic }
            NumberAnimation { target: loginPanel; property: "x"; to: 0; duration: 600; easing.type: Easing.OutCubic }
            NumberAnimation { target: info; property: "opacity"; to: 1; duration: 900; easing.type: Easing.OutCubic }
        }
        NumberAnimation { target: controls; property: "opacity"; to: 1; duration: 500 }
        ScriptAction {
            script: (userField.input.text === "" ? userField.input : passField.input).forceActiveFocus()
        }
    }
}
