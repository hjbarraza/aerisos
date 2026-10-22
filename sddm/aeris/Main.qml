// AerisOS login screen.
//
// One grid in a 1600x900 design space, scaled to fill the screen; fades in from black:
//   margins 96 left/right, text rows at y=96 (top) and y=820 (bottom)
//   left two-thirds  x 96–960: wordmark, tagline, rule, then the info cards stacked one per row
//   right third     x 1120–1504, beside a hairline at x=1040: the login on one row (user | password)
//                   beside the wordmark (status on its baseline), then the Iran digest from the
//                   ontology map, and the news from the tagline's baseline down to the power row
// Every card is a row: its head (white) at x=96, then a two-line table of key/value pairs in three
// columns. Keys are flush right against their value (10 apart) so each pair reads as one; pairs are
// 40 apart; values start at 294, 604 and 904. Lines are 18 apart; the cards spread down to 820
// with a hairline between. Under each card's name: when its data was fetched. Alerts from
// status.json (GNSS jammed, emergency squawk, ISS/CSS overhead, geomagnetic storm, an outage
// in this country) read inverted. The news wraps full headlines at 44 characters: Söhne Mono at 12 px
// + 1.5 tracking is ~8.65 per character, and the column is 384 wide.
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

    // Grid
    readonly property real gridLeft: 96
    readonly property real gridRight: 1504
    readonly property real infoRight: 960
    readonly property real panel: 1120              // login and news column
    readonly property var keyEnd: [284, 594, 894]   // card table: keys end here,
    readonly property var valueAt: [294, 604, 904]  // values start here,
    readonly property real headIndent: 25.6         // a head's name, after its slashes
    readonly property var valueRoom: [220, 210, 56] // and fit this (to the next column's longest key)
    readonly property real lineGap: 18
    readonly property real headGap: 26              // a column head (AUTHENTICATE, WORLD) to its first line
    readonly property real cardTop: 402             // first card line, 38 under the rule
    // Cards spread over the whole height: the last card's second line lands on 820
    readonly property real cardGap: (820 - lineGap - cardTop) / Math.max(1, cards.length - 1)
    readonly property real loginHead: 178           // beside the wordmark: head at its cap height,
    readonly property real statusBy: 280            // typed text on 240, status on its baseline
    readonly property real newsHead: 324            // the Iran digest, and the news below, from the tagline's baseline down
    readonly property real fieldWidth: 176          // user | 32 | password = 384
    readonly property real newsBottom: 784          // last news line, 36 above the power row
    // The Iran digest: the map's curated recent developments, one pre-wrapped line per row,
    // then a hairline and the news. The digest's height sets where WORLD starts.
    readonly property var iranItems: (d.iran && d.iran.items) || []
    readonly property int iranLines: Math.min(14, iranItems.reduce((n, it) => n + (it.lines ? it.lines.length : 1), 0))
    readonly property real iranLastBy: newsHead + headGap + (Math.max(iranLines, 1) - 1) * lineGap
    readonly property real worldHead: iranLines ? iranLastBy + 27 : newsHead
    readonly property int newsRows: Math.floor((newsBottom - worldHead - headGap) / lineGap) + 1

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

    function outage(i) {
        const o = ((d.world && d.world.outage_top) || [])[i]
        return o ? c(o[0], o[1]) : null
    }

    // One row per card; each line has three cells (null leaves one empty)
    readonly property var cards: [
        { en: "IDENTITY", fresh: d.updated || "—", lines: [
            [c("MODEL", g("identity", "model")), c("GPU", g("identity", "gpu")), c("HOST", g("identity", "host"))],
            [c("CPU", g("identity", "cpu")), null, c("RAM", g("identity", "ram"))] ] },
        { en: "STATUS", fresh: d.updated || "—", lines: [
            [c("POWER", g("state", "battery") + " · " + g("state", "power")), c("DISK", g("state", "disk")), c("CPU", g("state", "cpu_temp"))],
            [c("KERNEL", g("identity", "kernel").split("-")[0]), c("UP", g("state", "uptime")), c("BOOT", g("identity", "boot"))] ] },
        { en: "LOCATION", fresh: g("net", "fresh"), lines: [
            [c("CITY", g("net", "city")), c("LAT", g("net", "coords").split("  ")[0] || "—"), c("ALT", g("net", "alt"))],
            [c("TZ", g("net", "timezone")), c("LON", g("net", "coords").split("  ")[1] || "—"), c("UTC", g("local", "utc"))] ] },
        { en: "WEATHER", fresh: g("net", "fresh"), lines: [
            [c("SKY", g("net", "sky")), c("WIND", g("net", "wind")), c("TEMP", g("net", "temp"))],
            [c("RISE", g("net", "sunrise")), c("SET", g("net", "sunset")), c("HUM", g("net", "humidity"))] ] },
        { en: "SECURITY", fresh: d.updated || "—", lines: [
            [c("LAST", g("security", "last_login")),
             c("SYNC", (d.updated || "—") + (["net", "air", "space", "world"].some(k => d[k] && d[k].stale) ? " · OFFLINE" : "")),
             c("FAILED", g("security", "failed"))],
            [c("SNAPSHOT", g("security", "snapshot")), c("UPDATES", g("security", "updates")),
             c("FIREWALL", g("security", "firewall") === "ACTIVE" ? "ON" : g("security", "firewall"))] ] },
        { en: "AIRSPACE", fresh: g("air", "fresh"), lines: [
            [c("TRAFFIC", g("air", "traffic")), c("NEAREST", g("air", "nearest")), c("MIL", g("air", "mil"))],
            [c("GNSS", first(g("air", "gnss")), "air.gnss"), c("SQUAWK", g("air", "emergency"), "air.emergency"),
             c("GPSJAM", first(g("air", "jam_zones")))] ] },
        { en: "ORBIT", fresh: g("space", "fresh"), lines: [
            [c("ISS", g("space", "iss"), "space.iss"), c("CSS", g("space", "css"), "space.css"), c("KP", first(g("space", "kp")))],
            [c("NOAA", g("space", "scales") + " · " + rest(g("space", "kp")), "space.scales"), c("FLARE", g("space", "flare")), null] ] },
        { en: "INTERNET", fresh: g("world", "fresh_outages"), lines: [
            [c("OUTAGES", g("world", "outages"), "world.outages"), outage(0), c("PING", g("local", "ping"))],
            [outage(1), outage(2), c("DNS", g("local", "dns"))] ] }
    ]

    // Iran digest rows: white, one line each, no blanks; the map supplies them pre-wrapped
    readonly property var iran: {
        const rows = []
        for (const it of iranItems) {
            const lines = it.lines && it.lines.length ? it.lines : [`${it.k} · ${it.v}`]
            if (rows.length + lines.length > 14)
                break
            for (const l of lines)
                rows.push(l)
        }
        return rows
    }

    // News rows: each story's wrapped headline (white), a blank line between; no source line;
    // only whole stories that fit in newsRows
    readonly property var news: {
        const rows = []
        for (const item of (d.world && d.world.items) || []) {
            const lines = item.lines || [item.title || ""]
            if (rows.length + lines.length > newsRows)
                break
            for (const l of lines)
                rows.push({ t: l, source: false })
            if (rows.length < newsRows)
                rows.push({ t: "", source: false })
        }
        return rows.length ? rows : [{ t: "—", source: false }]
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

        // Divider between the information and the login
        Rectangle { x: 1040 * root.s; y: 80 * root.s; width: Math.max(1, root.s); height: 756 * root.s; color: root.hairline }

        // ---- live information: cards stacked under the rule, news in the right column ----

        Item {
            id: info
            opacity: 0
            width: parent.width; height: parent.height

            Repeater {
                model: root.cards
                delegate: Item {
                    id: card
                    readonly property real cy: root.cardTop + index * root.cardGap
                    Head { bx: root.gridLeft; by: card.cy; en: modelData.en }
                    // When this card's data was fetched, under its name
                    Label { bx: root.gridLeft + root.headIndent; by: card.cy + root.lineGap; text: modelData.fresh }
                    // Hairline halfway between this card's last baseline and the next card's cap height
                    Rectangle {
                        visible: index < root.cards.length - 1
                        x: root.gridLeft * root.s; y: (card.cy + (9 + root.cardGap) / 2) * root.s
                        width: (root.infoRight - root.gridLeft) * root.s; height: Math.max(1, root.s)
                        color: root.hairline
                    }
                    Repeater {
                        model: modelData.lines
                        delegate: Item {
                            id: line
                            readonly property real ly: card.cy + index * root.lineGap
                            readonly property var cells: modelData
                            Repeater {
                                model: 3
                                delegate: Item {
                                    readonly property var cell: line.cells[index]
                                    // Key (grey, 11), flush right against its value
                                    Label { visible: !!cell; bx: root.keyEnd[index]; by: line.ly; alignRight: true; text: cell ? cell.k : "" }
                                    // Value (white, 12)
                                    Label {
                                        visible: !!cell
                                        bx: root.valueAt[index]; by: line.ly
                                        width: Math.min(implicitWidth, root.valueRoom[index] * root.s)
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        font.pixelSize: 12 * root.s
                                        font.letterSpacing: 1.5 * root.s
                                        color: cell && cell.alert ? "#000000" : root.white
                                        text: cell ? cell.v : ""
                                        // Alerts read inverted: black on white
                                        Rectangle {
                                            z: -1
                                            visible: !!cell && cell.alert
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
            }

            // Right column: the Iran ontology digest, then the news
            Head { bx: root.panel; by: root.newsHead; en: "IRAN" }
            Label { bx: root.gridRight; by: root.newsHead; alignRight: true; text: g("iran", "fresh") + " · " + g("iran", "via") }
            Repeater {
                model: root.iran
                delegate: Label {
                    bx: root.panel; by: root.newsHead + root.headGap + index * root.lineGap
                    width: Math.min(implicitWidth, (root.gridRight - root.panel) * root.s)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: modelData
                }
            }
            Rectangle {
                visible: root.worldHead > root.newsHead
                x: root.panel * root.s; y: (root.iranLastBy + 13.5) * root.s
                width: (root.gridRight - root.panel) * root.s; height: Math.max(1, root.s)
                color: root.hairline
            }

            // News: below the digest, down to the power row
            Head { bx: root.panel; by: root.worldHead; en: "WORLD" }
            Label { bx: root.gridRight; by: root.worldHead; alignRight: true; text: g("world", "fresh_news") + " · " + g("world", "via") }
            Repeater {
                model: root.news
                delegate: Label {
                    bx: root.panel; by: root.worldHead + root.headGap + index * root.lineGap
                    width: Math.min(implicitWidth, (root.gridRight - root.panel) * root.s)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: (modelData.source ? 11 : 12) * root.s
                    font.letterSpacing: (modelData.source ? 2 : 1.5) * root.s
                    color: modelData.source ? root.grey : root.white
                    text: modelData.t
                }
            }
        }

        // ---- login: right third ----

        Item {
            id: loginPanel
            opacity: 0
            x: 16 * root.s
            width: parent.width; height: parent.height

            Head { bx: root.panel; by: root.loginHead; en: "AUTHENTICATE" }

            Field {
                id: userField
                bx: root.panel; by: root.loginHead + root.headGap + 2 * root.lineGap   // 324, caption on 288
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

        // ---- bottom row: power, under the login (the session is always the last one used) ----

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
