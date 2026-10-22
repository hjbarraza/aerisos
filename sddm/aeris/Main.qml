// AerisOS login screen.
//
// One grid in a 1600x900 design space, scaled to fill the screen; fades in from black.
// Same layout as the lock screen (lock/make-hyprlock), so both screens line up:
//   margins 96 left/right, text rows at y=96 (top) and y=820 (bottom)
//   left two-thirds  x 96–1120: wordmark, tagline and rule, then the feeds under them —
//                    WATCHLIST (the week's findings, one telegraphed line each, * = new)
//                    and WORLD (bulleted telegrams, whole stories only)
//   right third      x 1224–1504, beside a hairline at x=1160: the login on one row
//                    (user | password) beside the wordmark (status on its baseline), then
//                    the cards stacked under it, one key/value per row — LOCATION,
//                    AIRSPACE, ORBIT, INTERNET, each trimmed to its essential fields.
// IDENTITY, WEATHER, NETWORK and SECURITY are left out on purpose: the login screen is
// what people see when the laptop is left unattended. Keys are flush right against their
// values (10 apart); lines are 18 apart. Alerts from status.json (GNSS jammed, emergency
// squawk, ISS/CSS overhead, geomagnetic storm, an outage in this country) read inverted.
// Type scale: wordmark 144 · heads 13 (//)/11 white · values 12 · keys and labels 11.

import QtQuick 2.15
import QtQuick.Window 2.15

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#000000"

    // 1600x900 design space, scaled uniformly and centred
    readonly property real s: Math.min(width / 1600, height / 900)
    readonly property color white: "#ffffff"
    readonly property color grey: "#7a7a7a"
    readonly property color dim: "#3a3a3a"
    readonly property color hairline: "#262626"
    readonly property string sans: config.Font || "Söhne"
    readonly property string mono: config.MonoFont || "Söhne Mono"
    readonly property string jp: config.JapaneseFont || "Source Han Sans JP"

    // Grid, as in lock/make-hyprlock (the wordmark sits lower here: 280/324/364)
    readonly property real gridLeft: 96
    readonly property real gridRight: 1504
    readonly property real panel: 1224               // login and cards column
    readonly property real keyEnd: 1320              // right-column cards: keys end here,
    readonly property real valueAt: 1330             // values start here
    readonly property real feedRight: 1120           // the feeds' fresh timestamps right-align here
    readonly property real lineGap: 18
    readonly property real headGap: 26               // a column head (WATCHLIST, WORLD) to its first line
    readonly property real cardGap: 30               // vertical space between stacked cards
    readonly property real loginHead: 178            // beside the wordmark: head at its cap height,
    readonly property real statusBy: 280             // typed text on 240, status on its baseline
    readonly property real cardTop: 324              // first card head, under the status row
    readonly property real fieldWidth: 128           // user | gap | password across the column
    readonly property real watchHead: 404            // watchlist feed, 40 under the rule
    readonly property int watchRows: 14              // the lock shows 16; the lower wordmark costs two
    readonly property real worldHead: watchHead + headGap + watchRows * lineGap + 44   // 726
    readonly property int newsRows: 4                // last line lands on 806, above the power row

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
    // First word of a value ("2.0 QUIET" -> "2.0") and the rest
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
    // Each card's head baseline: stacked from cardTop, cardGap apart
    readonly property var cardTops: {
        const tops = []
        let cy = cardTop
        for (const card of cards) {
            tops.push(cy)
            cy += headGap + card.pairs.length * lineGap + cardGap
        }
        return tops
    }

    // Watchlist rows: pre-formatted by aeris-status (status.json watch.rows), the same
    // lines the lock screen shows; * marks unacknowledged findings
    readonly property var watch: {
        const rows = ((d.watch && d.watch.rows) || []).slice(0, watchRows)
        return rows.length ? rows : ["—"]
    }
    readonly property string watchFresh: {
        if (d.watch && d.watch.fresh)
            return String(d.watch.fresh)
        const checked = ((d.watch && d.watch.items) || []).map(i => i.checked || "").sort().pop()
        return checked ? checked.slice(-5) : "—"
    }

    // News rows: the pre-telegraphed stories (status.json world.telegrams), whole
    // stories only, as many as fit
    readonly property var news: {
        const rows = []
        for (const lines of (d.world && d.world.telegrams) || []) {
            if (rows.length + lines.length > newsRows)
                break
            for (const l of lines)
                rows.push(l)
        }
        return rows.length ? rows : ["—"]
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
        x: alignRight ? bx * root.s - width : bx * root.s
        y: by * root.s - baselineOffset
    }

    // Text button
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

    // Section head: a white slash, then the name
    component Head: Item {
        property real bx: 0
        property real by: 0
        property string en: ""
        Text {
            id: slash
            text: "//"
            font.family: root.mono
            font.pixelSize: 13 * root.s
            color: root.white
            x: parent.bx * root.s
            y: parent.by * root.s - baselineOffset
        }
        Label {
            bx: (slash.x + slash.width + 10 * root.s) / root.s
            by: parent.by
            text: parent.en
            color: root.white
        }
    }

    // Underlined input; its caption sits two lines (36) above the typed text, the rule 12 below
    component Field: Item {
        property alias input: field
        property string caption: ""
        property real bx: 0
        property real by: 0          // baseline of the typed text
        x: bx * root.s
        y: (by - 48) * root.s
        property real w: 384
        width: w * root.s
        height: 61 * root.s
        Label { bx: 0; by: 12; text: parent.caption; color: field.activeFocus ? root.white : root.grey }
        TextInput {
            id: field
            x: 0
            y: 48 * root.s - baselineOffset
            width: parent.width
            font.family: root.mono
            font.pixelSize: 16 * root.s
            font.letterSpacing: 2 * root.s
            color: root.white
            selectionColor: root.grey
            clip: true
        }
        Rectangle {
            y: 60 * root.s
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

        Label { bx: root.gridLeft; by: 96; text: config.SystemLabel || "SYS/00" }
        Label { bx: 960; by: 96; alignRight: true; text: config.BuildLabel || "BUILD 2026.10" }
        Label {
            id: clockLabel
            bx: root.gridRight; by: 96; alignRight: true
            color: root.white
            function update() {
                const now = new Date()
                text = Qt.formatDateTime(now, "ddd dd MMM yyyy").toUpperCase() + "   " + Qt.formatTime(now, "HH:mm")
            }
            Component.onCompleted: update()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: clockLabel.update() }
        }

        // Wordmark: ÆRIS regular (with the Æ ligature), OS bold
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
                y: 280 * root.s - baselineOffset
            }
        }

        Label {
            bx: root.gridLeft; by: 324
            font.pixelSize: 12 * root.s
            color: root.white
            text: "INTELLIGENCE OPERATING SYSTEM"
        }
        Text {
            text: "知能情報システム"
            font.family: root.jp
            font.pixelSize: 12 * root.s
            font.letterSpacing: 2 * root.s
            color: root.grey
            x: 960 * root.s - width
            y: 324 * root.s - baselineOffset
        }

        // Rule, with a light bead sweeping along it
        Item {
            x: root.gridLeft * root.s; y: 362.5 * root.s
            width: 864 * root.s; height: 4 * root.s
            clip: true
            Rectangle { y: 1.5 * root.s; width: parent.width; height: Math.max(1, root.s); color: root.white }
            Rectangle {
                id: sweep
                width: 140 * root.s; height: parent.height
                x: -width
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#ffffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
                SequentialAnimation on x {
                    loops: Animation.Infinite
                    NumberAnimation { from: -sweep.width; to: 864 * root.s; duration: 1800; easing.type: Easing.InOutQuad }
                    PauseAnimation { duration: 2600 }
                }
            }
        }

        // Divider between the feeds and the login column
        Rectangle { x: 1160 * root.s; y: 80 * root.s; width: Math.max(1, root.s); height: 756 * root.s; color: root.hairline }

        // ---- live information: feeds in the wide left column, cards under the login ----

        Item {
            id: info
            opacity: 0
            width: parent.width; height: parent.height

            // Feed line: white, one row, cut by the collector to the column
            component FeedRow: Label {
                width: Math.min(implicitWidth, (root.feedRight - root.gridLeft) * root.s)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.pixelSize: 12 * root.s
                font.letterSpacing: 1.5 * root.s
                color: root.white
            }

            Head { bx: root.gridLeft; by: root.watchHead; en: "WATCHLIST" }
            Label { bx: root.feedRight; by: root.watchHead; alignRight: true; text: root.watchFresh }
            Repeater {
                model: root.watch
                delegate: FeedRow {
                    bx: root.gridLeft; by: root.watchHead + root.headGap + index * root.lineGap
                    text: modelData
                }
            }

            Head { bx: root.gridLeft; by: root.worldHead; en: "WORLD" }
            Label { bx: root.feedRight; by: root.worldHead; alignRight: true; text: g("world", "fresh_news") + " · " + g("world", "via") }
            Repeater {
                model: root.news
                delegate: FeedRow {
                    bx: root.gridLeft; by: root.worldHead + root.headGap + index * root.lineGap
                    text: modelData
                }
            }

            // Cards stacked in the right column, under the login
            Repeater {
                model: root.cards
                delegate: Item {
                    id: card
                    readonly property real cy: root.cardTops[index]
                    Head { bx: root.panel; by: card.cy; en: modelData.en }
                    // When this card's data was fetched, on its head's baseline
                    Label { bx: root.gridRight; by: card.cy; alignRight: true; text: modelData.fresh }
                    Repeater {
                        model: modelData.pairs
                        delegate: Item {
                            readonly property real ly: card.cy + root.headGap + index * root.lineGap
                            readonly property var cell: modelData
                            // Key (grey, 11), flush right against its value
                            Label { bx: root.keyEnd; by: parent.ly; alignRight: true; text: cell.k }
                            // Value (white, 12)
                            Label {
                                bx: root.valueAt; by: parent.ly
                                width: Math.min(implicitWidth, (root.gridRight - root.valueAt) * root.s)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.pixelSize: 12 * root.s
                                font.letterSpacing: 1.5 * root.s
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

        // ---- login: right third, beside the wordmark ----

        Item {
            id: loginPanel
            opacity: 0
            x: 16 * root.s
            width: parent.width; height: parent.height

            Head { bx: root.panel; by: root.loginHead; en: "AUTHENTICATE" }

            Field {
                id: userField
                bx: root.panel; by: root.loginHead + root.headGap + 2 * root.lineGap   // 240, caption on 204
                w: root.fieldWidth
                caption: "USER"
                input.text: userModel.lastUser
                input.KeyNavigation.tab: passField.input
                input.onAccepted: passField.input.forceActiveFocus()
            }
            Field {
                id: passField
                bx: root.gridRight - root.fieldWidth; by: userField.by
                w: root.fieldWidth
                caption: "PASSWORD"
                input.echoMode: TextInput.Password
                input.passwordCharacter: "•"
                input.KeyNavigation.backtab: userField.input
                input.onAccepted: root.login()
            }

            Label {
                id: statusLabel
                bx: root.panel; by: root.statusBy
                text: root.status + (keyboard.capsLock ? " · CAPS LOCK" : "")
                color: root.status === "ACCESS DENIED" ? root.white : root.grey
            }
            Action {
                bx: root.gridRight; by: statusLabel.by; alignRight: true
                font.pixelSize: 12 * root.s
                text: "ENTER →"
                onActivated: root.login()
            }
        }

        // ---- bottom row: power, under the cards (the session is always the last one used) ----

        Item {
            id: controls
            opacity: 0
            width: parent.width; height: parent.height

            Action {
                id: sleepAction
                bx: root.panel; by: 820; text: "SLEEP"
                visible: sddm.canSuspend
                onActivated: sddm.suspend()
            }
            Action {
                id: restartAction
                bx: (sleepAction.visible ? sleepAction.x + sleepAction.width + 32 * root.s : root.panel * root.s) / root.s
                by: 820; text: "RESTART"
                visible: sddm.canReboot
                onActivated: sddm.reboot()
            }
            Action {
                bx: root.gridRight; by: 820; alignRight: true; text: "SHUT DOWN"
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
