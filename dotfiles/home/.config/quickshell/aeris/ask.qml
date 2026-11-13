import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Ask the pet, opened by Super + / (aeris-ask). It grows only when it has to:
//
//   1. A one-line input right under the pet, labelled YOU. It takes the keyboard as soon as it
//      opens (exclusive layer focus), so typing lands here; dictation is fetched (see Dictation).
//   2. A short answer is said whole in the pet's own tiny bubble; the input stays open,
//      ready for a follow-up.
//   3. A follow-up, or an answer too long for the bubble (LONG_ANSWER, same as aeris-ask),
//      turns the input into a chat card with the conversation; from then on the bubble only
//      gets a short reaction, so nothing shows twice.
//
// The pet can look things up on the laptop: aeris-ask runs commands that TypeSafe Jev judges
// harmless (shown as RAN), asks here for the rest (RUN?: Enter runs it, Escape skips it) and
// never runs what Jev refuses. aeris-ask --chat prints one JSON line per event:
// {"type": "ran" | "confirm" | "answer", "command" | "text"}.
//
// Swiss layout, black and white: an 8 px grid; two columns (96 px labels in small tracked
// capitals, hung on the first baseline of the text; a 16 px gutter; the text column); one
// family in two sizes (15 px text on 24 px lines, 11 px labels); a 1 px white frame with
// Hyprland's 6 px corners, 1 px grey hairlines; your words grey, the pet's white; commands in mono. A 1 px leader
// line rises from the card to the pet. The card follows the pet in 8 px steps (both pets write
// where they are to $XDG_RUNTIME_DIR/aeris-pet/pos.json) and carries its name.
//
// Slash commands (/news, /timer 25m, /comic, /help…) are answered by aeris-ask without the
// model; typing "/" lists the matching ones above the input (Tab completes the first). Their
// replies arrive as extra events: "clear", "list" (label | value rows) and "image" (/comic).
// Test hook: AERIS_ASK_DEMO="/news" submits that on open; a trailing "…" only types it.
//
// Escape, Super + / or a click outside it closes it and forgets the chat; it also closes itself after two idle
// minutes with nothing typed.
//   qs -p ~/.config/quickshell/aeris/ask.qml
ShellRoot {
    PanelWindow {
        id: box
        readonly property int u: 8                       // the grid unit
        readonly property int labelCol: 12 * u           // 96
        readonly property int gutter: 2 * u              // 16
        readonly property int pad: 2 * u                 // 16 inside the frame
        readonly property int leader: u                  // the line up towards the pet (to its bubble)
        readonly property int textSize: 15
        readonly property int lineH: 3 * u               // 24
        readonly property int labelSize: 11
        readonly property int longAnswer: 110
        readonly property color grey: "#8c8c8c"
        readonly property color hair: "#2a2a2a"

        readonly property real screenW: screen ? screen.width : 1366
        readonly property real screenH: screen ? screen.height : 768
        property bool busy: false
        property bool expanded: false   // the chat log is showing
        property string pendingCmd: ""  // a command waiting for Enter (run) or Escape (skip)
        property int asked: 0
        property real petX: screenW / 2
        property real petY: 0
        property string petWhere: "bar"
        property string petKind: "raven"
        readonly property string petName: ({ raven: "tinyraven", dragon: "tinydragon" })[petKind] ?? petKind

        function snap(v) { return Math.round(v / u) * u }

        anchors { top: true; left: true }
        // the window starts `leader` px above the card, so the leader line can reach up
        margins.left: snap(Math.max(u, Math.min(screenW - implicitWidth - u, petX - implicitWidth / 2)))
        margins.top: (petWhere === "bar" ? Theme.barHeight + 9 * u
                      : (petY + 8 * u + implicitHeight < screenH - u
                         ? petY + 8 * u : Math.max(Theme.barHeight + u, petY - 9 * u - implicitHeight))) - leader
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: expanded ? 70 * u : 54 * u         // 560 / 432
        implicitHeight: leader + frame.height
        color: "transparent"
        mask: Region { item: frame }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aeris-ask"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Dictation. Superwhisper won't type into a panel that holds the keyboard (it pastes into
        // app windows, and its fcitx5 add-on checks the target by app name, which a panel lacks),
        // so it falls back to the clipboard. While open, the box asks Superwhisper for its latest
        // dictation and takes any that fell back after the box opened, straight into the input.
        readonly property real openedAt: Date.now() / 1000
        property real lastDictation: 0
        Timer {
            interval: 400; running: true; repeat: true
            onTriggered: if (!dictation.running) dictation.running = true
        }
        Process {
            id: dictation
            command: [Quickshell.env("HOME") + "/.local/bin/superwhisper", "read"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let d
                    try { d = JSON.parse(text) } catch (e) { return }
                    const t = (d.inserted_text || "").trim()
                    if (!t || !(d.createdAt >= box.openedAt - 1) || d.createdAt <= box.lastDictation) return
                    if (d.delivery !== "clipboard" && d.delivery !== "paste_sent") return
                    box.lastDictation = d.createdAt
                    if (d.delivery === "clipboard") {      // not typed into the box: insert it here
                        const before = input.text.slice(0, input.cursorPosition)
                        const gap = before.length && !/\s$/.test(before) ? " " : ""
                        input.insert(input.cursorPosition, gap + t)
                    }
                    input.forceActiveFocus()
                    idle.restart()
                    autoSend.restart()
                }
            }
        }
        // Auto-submit: a dictation is sent like Enter, unless `sw-autosubmit off` paused it.
        Timer { id: autoSend; interval: 300; onTriggered: autoSendCheck.running = true }
        Process {
            id: autoSendCheck
            command: ["test", "-e", Quickshell.env("HOME") + "/.local/state/aeris/autosubmit-off"]
            onExited: (code) => { if (code !== 0) box.send() }
        }

        ListModel { id: chat }
        // slash commands, from aeris-ask itself: [[name, usage, summary]]; typing "/" lists the matches
        property var commands: []
        readonly property var matches: {
            const t = input.text
            if (!t.startsWith("/") || t.includes(" ") || pendingCmd) return []
            return commands.filter(c => ("/" + c[0]).startsWith(t.toLowerCase())).slice(0, 8)
        }
        Process {
            running: true
            command: [Quickshell.env("HOME") + "/.local/bin/aeris-ask", "--commands"]
            stdout: StdioCollector { onStreamFinished: { try { box.commands = JSON.parse(text) } catch (e) {} } }
        }   // {who: "you" | "pet" | "ran" | "confirm" | "skipped", text}

        function send() {
            const q = input.text.trim()
            if (!q.length || busy || pendingCmd) return
            asked += 1
            if (asked > 1) expanded = true          // a follow-up: show the conversation
            chat.append({ who: "you", text: q })
            chat.append({ who: "pet", text: "…" })
            input.text = ""
            start(["--chat", "--", q])
        }
        function start(args) {
            busy = true
            idle.restart()
            asker.command = [Quickshell.env("HOME") + "/.local/bin/aeris-ask"].concat(args)
            asker.running = true
        }
        // the pet's events: commands it ran, a command it wants to run, its answer
        function handle(out) {
            let answered = false
            for (const line of out.split("\n")) {
                if (!line.trim()) continue
                let ev
                try { ev = JSON.parse(line) } catch (e) { ev = { type: "answer", text: line } }
                const last = chat.count - 1                     // the pet's "…" row
                if (ev.type === "ran") {
                    chat.insert(last, { who: "ran", text: ev.command + (ev.output ? "\n" + ev.output : "") })
                    expanded = true                             // show what it ran
                } else if (ev.type === "confirm") {
                    chat.setProperty(last, "text", "can i run this?")
                    chat.append({ who: "confirm", text: ev.command })
                    pendingCmd = ev.command
                    expanded = true
                    answered = true
                } else if (ev.type === "answer") {
                    chat.setProperty(last, "text", ev.text)
                    if (ev.text.length > longAnswer) expanded = true
                    answered = true
                } else if (ev.type === "clear") {               // /clear: a fresh, empty box
                    chat.clear()
                    expanded = false
                    asked = 0
                    return
                } else if (ev.type === "list") {                // /news, /status, /help…: label | value rows
                    chat.setProperty(last, "text", ev.title)
                    for (const r of ev.rows) chat.append({ who: "row:" + r[0], text: String(r[1]) })
                    expanded = true
                    answered = true
                } else if (ev.type === "image") {               // /comic: the picture, then its alt text
                    chat.setProperty(last, "text", ev.title)
                    chat.append({ who: "image", text: ev.path + "\n" + (ev.original || ev.path) })
                    if (ev.text) chat.append({ who: "row:alt", text: ev.text })
                    expanded = true
                    answered = true
                }
            }
            if (!answered) chat.setProperty(chat.count - 1, "text", "…nothing came back. try again?")
        }
        function decide(run) {   // Enter / Escape on a RUN? prompt
            chat.setProperty(chat.count - 1, "who", run ? "ran" : "skipped")
            chat.append({ who: "pet", text: "…" })
            pendingCmd = ""
            start([run ? "--approve" : "--decline"])
        }
        function close() {
            Quickshell.execDetached(["rm", "-f", Quickshell.env("XDG_RUNTIME_DIR") + "/aeris-pet/ask-chat.json",
                                     Quickshell.env("XDG_RUNTIME_DIR") + "/aeris-pet/ask-pending.json"])
            Qt.quit()
        }

        Process {
            id: asker
            stdout: StdioCollector {
                onStreamFinished: {
                    box.handle(text)
                    box.busy = false
                    idle.restart()
                }
            }
        }
        // closes itself when left alone (nothing typed, nothing pending) for two minutes
        Timer { id: idle; interval: 120000; running: true; onTriggered: if (!box.busy && !input.text.length) box.close(); else restart() }

        FileView {   // where the pet is; it moves, the box follows
            path: Quickshell.env("XDG_RUNTIME_DIR") + "/aeris-pet/pos.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: {
                try {
                    const j = JSON.parse(text())
                    box.petWhere = j.where ?? "bar"
                    box.petX = j.x ?? box.petX
                    box.petY = j.y ?? 0
                } catch (e) {}   // half-written; the next write comes soon
            }
        }
        FileView {   // which pet: its name labels the box
            path: Quickshell.env("HOME") + "/.local/state/aeris-pet/pet"
            printErrors: false
            watchChanges: true                       // /pet switches it while the box is open
            onFileChanged: reload()
            onLoaded: box.petKind = text().trim() || "raven"
        }

        // the leader line: from the card's top edge up towards the pet
        Rectangle {
            x: Math.round(Math.max(box.u, Math.min(box.width - box.u, box.petX - box.margins.left)))
            y: 0
            width: 1
            height: box.leader
            color: Theme.fg
            visible: box.petWhere === "bar" || box.petY < box.margins.top
        }

        Rectangle {
            id: frame
            y: box.leader
            width: parent.width
            height: col.height + 2 * box.pad
            color: "#000000"
            border.color: Theme.fg
            border.width: 1
            radius: 6   // like a Hyprland window (decoration.rounding = 6), one line or many

            Column {
                id: col
                x: box.pad; y: box.pad
                width: parent.width - 2 * box.pad
                spacing: box.u

                ListView {
                    id: log
                    width: parent.width
                    // as tall as the screen allows below the bar (lists, comics), then it scrolls
                    height: Math.min(contentHeight, box.screenH - Theme.barHeight - 9 * box.u - 5 * box.lineH)
                    visible: box.expanded && chat.count > 0
                    clip: true
                    spacing: box.u
                    model: chat
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: Qt.callLater(positionViewAtEnd)
                    onContentHeightChanged: Qt.callLater(positionViewAtEnd)
                    delegate: Item {
                        id: msg
                        required property string who
                        required property string text
                        readonly property bool isCmd: who === "ran" || who === "confirm" || who === "skipped"
                        readonly property bool isRow: who.startsWith("row:")
                        readonly property bool isImage: who === "image"
                        width: log.width
                        height: isImage ? pic.height : body.height
                        Text {   // label: hung on the text's first baseline
                            anchors.left: parent.left
                            anchors.baseline: body.baseline
                            width: box.labelCol
                            visible: !msg.isImage
                            text: (msg.who === "pet" ? box.petName
                                  : msg.who === "you" ? "you"
                                  : msg.isRow ? msg.who.slice(4)
                                  : msg.who === "confirm" ? "run?" : msg.who).toUpperCase()
                            color: msg.who === "confirm" ? Theme.fg : box.grey
                            elide: Text.ElideRight
                            font { family: Theme.sans; pixelSize: box.labelSize; weight: Font.Medium; letterSpacing: 0.9 }
                        }
                        TextEdit {   // selectable, so an answer or command can be copied
                            id: body
                            visible: !msg.isImage
                            x: box.labelCol + box.gutter
                            width: msg.width - x
                            text: msg.isImage ? "" : msg.text
                            readOnly: true
                            selectByMouse: true
                            wrapMode: Text.Wrap
                            color: msg.who === "pet" || msg.who === "confirm" || msg.isRow ? Theme.fg : box.grey
                            selectionColor: box.hair
                            font.family: msg.isCmd ? Theme.nerd : Theme.sans
                            font.pixelSize: msg.isCmd ? box.textSize - 2 : box.textSize
                            font.strikeout: msg.who === "skipped"
                            font.features: { "tnum": 1 }
                            // pad the line box out to the 24 px grid line
                            topPadding: Math.max(0, Math.round((box.lineH - font.pixelSize * 1.25) / 2))
                            bottomPadding: topPadding
                        }
                        Image {   // /comic: inverted, as wide as the card allows; click opens the original
                            id: pic
                            visible: msg.isImage
                            readonly property var paths: msg.text.split("\n")
                            source: msg.isImage ? "file://" + paths[0] : ""
                            cache: false
                            asynchronous: false
                            readonly property int maxH: 40 * box.u     // 320: a tall comic still fits with its alt text
                            width: msg.isImage && sourceSize.width > 0
                                   ? Math.min(sourceSize.width, msg.width, Math.round(maxH * sourceSize.width / sourceSize.height)) : 0
                            height: msg.isImage && sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["imv", pic.paths[1] || pic.paths[0]])
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: box.hair; visible: log.visible }

                Column {   // the "/" hint: matching commands, Tab completes the first
                    width: parent.width
                    visible: box.matches.length > 0
                    Repeater {
                        model: box.matches
                        Item {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: box.lineH
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: box.labelCol
                                text: "/" + modelData[0]
                                color: index === 0 ? Theme.fg : box.grey
                                font { family: Theme.nerd; pixelSize: box.textSize - 2 }
                            }
                            Text {
                                x: box.labelCol + box.gutter
                                width: parent.width - x
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData[2]
                                elide: Text.ElideRight
                                color: box.grey
                                font { family: Theme.sans; pixelSize: box.textSize }
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: box.hair; visible: box.matches.length > 0 }

                Item {   // the input row: YOU in the label column, the text in the text column
                    width: parent.width
                    height: box.lineH
                    Text {
                        anchors.left: parent.left
                        anchors.baseline: input.baseline
                        text: "YOU"
                        color: box.grey
                        font { family: Theme.sans; pixelSize: box.labelSize; weight: Font.Medium; letterSpacing: 0.9 }
                    }
                    TextInput {
                        id: input
                        x: box.labelCol + box.gutter
                        width: parent.width - x
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        selectionColor: box.hair
                        font { family: Theme.sans; pixelSize: box.textSize }
                        clip: true
                        focus: true
                        cursorDelegate: Rectangle {   // a white block cursor, blinking
                            width: box.u; height: box.textSize + 3
                            color: Theme.fg
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PropertyAction { value: 1 }
                                PauseAnimation { duration: 530 }
                                PropertyAction { value: 0 }
                                PauseAnimation { duration: 530 }
                            }
                        }
                        Component.onCompleted: {
                            forceActiveFocus()
                            // test hook: AERIS_ASK_DEMO="/news" submits that as soon as the box opens
                            const demo = Quickshell.env("AERIS_ASK_DEMO")
                            if (demo) { text = demo; if (!demo.endsWith("…")) Qt.callLater(box.send); else text = demo.slice(0, -1) }
                        }
                        onTextChanged: idle.restart()
                        Keys.onReturnPressed: box.pendingCmd ? box.decide(true) : box.send()
                        Keys.onEnterPressed: box.pendingCmd ? box.decide(true) : box.send()
                        Keys.onEscapePressed: box.pendingCmd ? box.decide(false) : box.close()
                        Keys.onTabPressed: if (box.matches.length) text = "/" + box.matches[0][0] + " "

                        Text {   // placeholder, on the text column's edge
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x
                            elide: Text.ElideRight
                            visible: !input.text.length
                            text: box.pendingCmd ? "enter runs it · esc skips it"
                                 : box.busy ? box.petName + " is thinking"
                                 : box.asked ? "follow up · esc to close"
                                 : "ask " + box.petName + " anything · / for commands"
                            color: "#5a5a5a"
                            font: input.font
                        }
                    }
                }
            }
        }
    }

    // Click outside to close: an invisible layer over every screen, under the box and the pet
    // (both on the overlay layer). A click anywhere else closes the box like Escape does, and
    // focus then follows the mouse to the window underneath. It never takes the keyboard.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "aeris-ask-scrim"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: box.close()
            }
        }
    }
}
