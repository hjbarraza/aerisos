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
//   top row 99        SYS/00 · date and time over the panel
//   wordmark 243      ÆRIS OS; the login's field rules sit on its baseline
//   tagline 297       and the login status beside it
//   rule 324          broken by the gutter between the two columns
//   heads 369 ...     WATCHLIST and WORLD as tables (date | topic or outlet | telegram, the
//                     date only where it changes, unread marked in the margin), the cards
//                     (key flush right against value) beside them; a head's rows follow it
//                     directly, one blank row between groups, and the last feed row and the
//                     last card row share a baseline (765)
//   bottom row 819    build · power
//
// IDENTITY, WEATHER, NETWORK and SECURITY are left out on purpose: the login screen is
// what people see when the laptop is left unattended. Alerts from status.json read inverted.
// Type: wordmark Söhne 144; everything else Söhne Mono, values 12 white, keys and labels 11 grey.

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
    readonly property string sans: config.Font || "Söhne"
    readonly property string mono: config.MonoFont || "Söhne Mono"
    readonly property string jp: config.JapaneseFont || "Source Han Sans JP"

    // ---- grid ----
    function col(n) { return 96 + 120 * (n - 1) }          // left edge of column n
    function colEnd(n) { return col(n) + 88 }               // right edge of column n
    readonly property real gridLeft: 96
    readonly property real gridRight: 1504
    readonly property real feedRight: 1144                 // end of column 9
    readonly property real panel: 1176                     // column 10
    readonly property real valueAt: 1296                   // column 11: card values, password
    readonly property real keyEnd: 1286                    // card keys end 10 before their values
    readonly property real line: 18
    readonly property real topRow: 99
    readonly property real bottomRow: 819
    readonly property real markBy: 243                     // wordmark baseline
    readonly property real tagBy: 297                      // tagline / login status
    readonly property real ruleY: 324
    readonly property real sectionTop: 369                 // WATCHLIST head and first card head
    readonly property int watchRows: 16
    readonly property real worldHead: sectionTop + (watchRows + 2) * line   // 693
    readonly property int newsRows: 4                      // last row on 765
    readonly property var feedCols: [col(1), col(2), col(4)]   // date | topic | telegram

    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string status: "AWAITING AUTHENTICATION"
    property bool busy: false

    // ---- live info (written by aeris-status.timer, re-read every 15 s) ----

    property var d: ({})
    function g(section, key) {
        const v = d[section] && d[section][key]
        return v ? String(v) : "—"
    }
    // A card cell: key, value, and the status.json alert that inverts it
    function c(k, v, alert) {
        return { k: k, v: v, alert: !!alert && (d.alerts || []).indexOf(alert) >= 0 }
    }
    function first(v) { return v.split(" ")[0] }
    function rest(v) { return v.split(" ").slice(1).join(" ") || "—" }
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

    // The right-column cards, trimmed to their essential fields, as on the lock screen
    readonly property var cards: [
        { en: "LOCATION", fresh: g("net", "fresh"), pairs: [
            c("LAT", g("net", "coords").split("  ")[0] || "—"),
            c("LON", g("net", "coords").split("  ")[1] || "—"),
            c("UTC", g("local", "utc")) ] },
        { en: "AIRSPACE", fresh: g("air", "fresh"), pairs: [
            c("TRAFFIC", g("air", "traffic")),
            c("NEAREST", g("air", "nearest")),
            c("GNSS", first(g("air", "gnss")), "air.gnss"),
            c("SQUAWK", g("air", "emergency"), "air.emergency") ] },
        { en: "ORBIT", fresh: g("space", "fresh"), pairs: [
            c("ISS", g("space", "iss"), "space.iss"),
            c("CSS", g("space", "css"), "space.css"),
            c("KP", first(g("space", "kp"))),
            c("NOAA", g("space", "scales") + " · " + rest(g("space", "kp")), "space.scales"),
            c("SATS", g("space", "sats")),
            c("LAUNCH", g("space", "launch")),
            c("T-0", g("space", "launch_t0")) ] },
        { en: "INTERNET", fresh: g("world", "fresh_outages"), pairs: [
            c("OUTAGES", g("world", "outages"), "world.outages"),
            c("PING", g("local", "ping")) ] }
    ]
    // Card heads: a head, its rows directly under it, one blank row between cards
    readonly property var cardTops: {
        const tops = []
        let cy = sectionTop
        for (const card of cards) {
            tops.push(cy)
            cy += (card.pairs.length + 2) * line
        }
        return tops
    }

    // Watchlist: status.json watch.rows ("* 12 NOV · TOPIC · TELEGRAM", the lines the lock
    // screen splits the same way) as table cells; the date shows only where it changes,
    // * (unread) becomes a square in the margin
    readonly property var watch: {
        const rows = ((d.watch && d.watch.rows) || []).slice(0, watchRows)
        let last = ""
        return rows.map(r => {
            const parts = r.slice(2).split(" · ")
            if (parts.length < 3)
                return { fresh: false, a: "", b: "", c: r.slice(2) }
            const day = parts[0]
            const cell = { fresh: r[0] === "*", a: day === last ? "" : day, b: parts[1], c: parts.slice(2).join(" · ") }
            last = day
            return cell
        })
    }
    readonly property string watchFresh: d.watch && d.watch.fresh ? String(d.watch.fresh) : "—"

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
                            a: j ? "" : (src[1] || ""),
                            b: j ? "" : src[0].replace(/\.(com|media|org|net|co\.uk)$/i, ""),
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

    // Section head: // and the name in white, its fetch time right-aligned on the baseline
    component Head: Item {
        property real bx: 0
        property real by: 0
        property real rightX: 0
        property string en: ""
        property string fresh: ""
        Label { bx: parent.bx; by: parent.by; text: "//  " + parent.en; color: root.white }
        Label { bx: parent.rightX; by: parent.by; alignRight: true; text: parent.fresh }
    }

    // A feed table: date | topic or outlet | telegram, one row per line under the head
    component Feed: Item {
        property real by: 0
        property var rows: []
        Repeater {
            model: parent.rows
            delegate: Item {
                readonly property real ly: parent.by + (index + 1) * root.line
                Rectangle {   // unread: a small square hanging in the margin
                    visible: modelData.fresh
                    x: (root.gridLeft - 14) * root.s; y: (ly - 7) * root.s
                    width: 5 * root.s; height: 5 * root.s
                    color: root.white
                }
                Label { bx: root.feedCols[0]; by: ly; text: modelData.a; color: modelData.fresh ? root.white : root.grey }
                Label { bx: root.feedCols[1]; by: ly; text: modelData.b }
                Value {
                    bx: root.feedCols[2]; by: ly
                    width: Math.min(implicitWidth, (root.feedRight - root.feedCols[2]) * root.s)
                    text: modelData.c
                    color: modelData.fresh || !modelData.a && !modelData.b && index === 0 ? root.white : root.read
                }
            }
        }
    }

    // Underlined input: caption 27 above the typed text, the rule 9 below it (by = the rule)
    component Field: Item {
        property alias input: field
        property string caption: ""
        property real bx: 0
        property real by: 0
        property real w: 128
        x: bx * root.s
        y: (by - 36) * root.s
        width: w * root.s
        height: 37 * root.s
        Label { bx: 0; by: 0; text: parent.caption; color: field.activeFocus ? root.white : root.grey }
        TextInput {
            id: field
            x: 0
            y: 27 * root.s - baselineOffset
            width: parent.width
            font.family: root.mono
            font.pixelSize: 16 * root.s
            font.letterSpacing: 2 * root.s
            color: root.white
            selectionColor: root.grey
            clip: true
        }
        Rectangle {
            y: 36 * root.s
            width: parent.width
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
        Label { bx: root.gridLeft; by: root.topRow; text: config.SystemLabel || "SYS/00" }
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

            Head { bx: root.gridLeft; by: root.sectionTop; rightX: root.feedRight; en: "WATCHLIST"; fresh: root.watchFresh }
            Feed { by: root.sectionTop; rows: root.watch }
            Head { bx: root.gridLeft; by: root.worldHead; rightX: root.feedRight; en: "WORLD"; fresh: g("world", "fresh_news") + " · " + g("world", "via") }
            Feed { by: root.worldHead; rows: root.news }

            Repeater {
                model: root.cards
                delegate: Item {
                    id: card
                    readonly property real cy: root.cardTops[index]
                    Head { bx: root.panel; by: card.cy; rightX: root.gridRight; en: modelData.en; fresh: modelData.fresh }
                    Repeater {
                        model: modelData.pairs
                        delegate: Item {
                            readonly property real ly: card.cy + (index + 1) * root.line
                            readonly property var cell: modelData
                            Label { bx: root.keyEnd; by: parent.ly; alignRight: true; text: cell.k }
                            Value {
                                bx: root.valueAt; by: parent.ly
                                width: Math.min(implicitWidth, (root.gridRight - root.valueAt) * root.s)
                                color: cell.alert ? "#000000" : root.white
                                text: cell.v
                                // Alerts read inverted: black on white
                                Rectangle {
                                    z: -1
                                    visible: cell.alert
                                    anchors.fill: parent
                                    anchors.leftMargin: -4 * root.s; anchors.rightMargin: -4 * root.s
                                    color: root.white
                                }
                            }
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
                bx: root.panel; by: root.markBy
                w: root.colEnd(10) - root.panel
                caption: "USER"
                input.text: userModel.lastUser
                input.KeyNavigation.tab: passField.input
                input.onAccepted: passField.input.forceActiveFocus()
            }
            Field {
                id: passField
                bx: root.valueAt; by: userField.by
                w: root.gridRight - root.valueAt
                caption: "PASSWORD"
                input.echoMode: TextInput.Password
                input.passwordCharacter: "•"
                input.KeyNavigation.backtab: userField.input
                input.onAccepted: root.login()
            }
            Label {
                id: statusLabel
                bx: root.panel; by: root.tagBy
                text: root.status + (keyboard.capsLock ? " · CAPS LOCK" : "")
                color: root.status === "ACCESS DENIED" ? root.white : root.grey
            }
            Action {
                bx: root.gridRight; by: root.tagBy; alignRight: true
                text: "ENTER →"
                onActivated: root.login()
            }
        }

        // ---- bottom row: build, power (the session is always the last one used) ----
        Item {
            id: controls
            opacity: 0
            width: parent.width; height: parent.height

            Label { bx: root.gridLeft; by: root.bottomRow; text: config.BuildLabel || "BUILD 2026.10" }
            Action {
                bx: root.panel; by: root.bottomRow; text: "SLEEP"
                visible: sddm.canSuspend
                onActivated: sddm.suspend()
            }
            Action {
                bx: root.valueAt; by: root.bottomRow; text: "RESTART"
                visible: sddm.canReboot
                onActivated: sddm.reboot()
            }
            Action {
                bx: root.gridRight; by: root.bottomRow; alignRight: true; text: "SHUT DOWN"
                visible: sddm.canPowerOff
                onActivated: sddm.powerOff()
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
