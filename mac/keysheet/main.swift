// Keysheet: a searchable cheat sheet for the skhd hotkeys in ~/.config/skhd/skhdrc.
// skhd launches it on cmd+K (`open -a Keysheet`); pressing again toggles it.
// The config is re-read every time the panel opens, so it never goes stale.
import AppKit

struct Hotkey { let keys: String; let spelled: String; let name: String; let group: String }

/// Parse skhdrc: a `# comment` names the group; each `mods - key : command` line is one hotkey.
func loadHotkeys() -> [Hotkey] {
    let path = NSString(string: "~/.config/skhd/skhdrc").expandingTildeInPath
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let symbols = ["cmd": "⌘", "ctrl": "⌃", "alt": "⌥", "shift": "⇧",
                   "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "space": "Space"]
    let names = ["cmd": "Cmd", "ctrl": "Ctrl", "alt": "Option", "shift": "Shift", "return": "Return", "space": "Space"]
    var group = "", out: [Hotkey] = []
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            // "Focus window (Hyprland: wm + arrows)" -> "Focus window"
            group = String(line.dropFirst()).components(separatedBy: "(")[0].trimmingCharacters(in: .whitespaces)
            continue
        }
        guard let colon = line.range(of: " : "), line.contains(" - ") else { continue }
        let combo = line[..<colon.lowerBound].replacingOccurrences(of: " ->", with: "") // skhd passthrough marker
        let parts = combo.components(separatedBy: " - ")
        let modList = parts[0].split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let mods = modList.map { symbols[$0] ?? "" }.joined(separator: " ")
        let key = parts[1].trimmingCharacters(in: .whitespaces)
        let isArrow = ["left", "right", "up", "down"].contains(key)
        let spelled = (modList + [key]).map { names[$0] ?? $0.capitalized }.joined(separator: " + ")
        out.append(Hotkey(keys: mods + " " + (symbols[key] ?? key.uppercased()), spelled: spelled,
                          name: isArrow ? "\(group) \(key)" : group, group: group))
    }
    return out
}

/// Söhne Mono (bundled in Resources), falling back to SF Mono for ⌘⌃⌥⇧↩, which Söhne Mono lacks.
func mono(_ size: CGFloat, bold: Bool = false) -> NSFont {
    let sf = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    guard let base = NSFont(name: bold ? "SohneMono-Kraftig" : "SohneMono-Buch", size: size) else { return sf }
    let d = base.fontDescriptor.addingAttributes([.cascadeList: [sf.fontDescriptor]])
    return NSFont(descriptor: d, size: size) ?? base
}

/// Söhne (bundled in Resources) for prose; falls back to the system font if missing.
func sans(_ size: CGFloat, bold: Bool = false) -> NSFont {
    NSFont(name: bold ? "Sohne-Kraftig" : "Sohne-Buch", size: size) ?? .systemFont(ofSize: size)
}

final class Panel: NSPanel { override var canBecomeKey: Bool { true } }

/// A list row is either a shortcut or a hairline break between groups.
enum Row { case key(Hotkey), rule }

/// Swiss layout on an 8pt grid: 40pt margins, three fixed columns, flush left.
let margin: CGFloat = 40, colKeys: CGFloat = 136, colName: CGFloat = 288

func label(_ text: String, _ font: NSFont, _ color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text); l.font = font; l.textColor = color
    l.translatesAutoresizingMaskIntoConstraints = false; return l
}

func hairline() -> NSBox {
    let b = NSBox(); b.boxType = .separator; b.translatesAutoresizingMaskIntoConstraints = false; return b
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
    let search = NSTextField(), table = NSTableView()
    let count = label("", mono(11), .secondaryLabelColor)
    var all: [Hotkey] = [], rows: [Row] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true; panel.level = .floating
        // Pure black in dark mode, pure white in light mode: no tint, no grey surface.
        panel.backgroundColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white }
        panel.delegate = self
        let bg = NSView(); panel.contentView = bg

        let title = label("WINDOW SHORTCUTS", sans(11, bold: true))
        title.attributedStringValue = NSAttributedString(string: title.stringValue,
            attributes: [.kern: 1.2, .font: sans(11, bold: true), .foregroundColor: NSColor.labelColor])

        search.placeholderString = "Type to filter"; search.delegate = self
        search.font = sans(24); search.isBordered = false; search.drawsBackground = false
        search.focusRingType = .none; search.translatesAutoresizingMaskIntoConstraints = false
        let rule = hairline()

        for (id, w) in [("keys", colKeys), ("name", colName), ("spelled", 240)] {
            let col = NSTableColumn(identifier: .init(id)); col.width = w; table.addTableColumn(col)
        }
        table.headerView = nil; table.backgroundColor = .clear; table.style = .plain
        table.intercellSpacing = .zero; table.selectionHighlightStyle = .none
        table.dataSource = self; table.delegate = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.drawsBackground = false
        scroll.hasVerticalScroller = false; scroll.translatesAutoresizingMaskIntoConstraints = false

        let hint = label("esc  close", mono(11), .tertiaryLabelColor)
        for v in [title, count, search, rule, scroll, hint] as [NSView] { bg.addSubview(v) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: bg.topAnchor, constant: margin),
            title.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            count.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            count.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            search.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin - 2),
            search.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            rule.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 16),
            rule.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            rule.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -16),
            hint.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            hint.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -32),
        ])
        show()
    }

    // Second cmd+K while open hides it; otherwise shows it.
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel.isVisible ? panel.orderOut(nil) : show()
        return false
    }

    func show() {
        all = loadHotkeys(); search.stringValue = ""; filter()
        // Center on the screen under the mouse.
        let mouse = NSEvent.mouseLocation
        if let f = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless(); panel.makeKey(); panel.makeFirstResponder(search)
    }

    func filter() {
        let words = search.stringValue.lowercased().split(separator: " ")
        let hits = all.filter { h in words.allSatisfy { "\(h.name) \(h.keys) \(h.spelled)".lowercased().contains($0) } }
        rows = []
        for (i, h) in hits.enumerated() {
            if i > 0 && hits[i - 1].group != h.group { rows.append(.rule) }
            rows.append(.key(h))
        }
        count.stringValue = String(format: "%02d / %02d", hits.count, all.count)
        table.reloadData()
    }

    // Clicking anywhere else closes it.
    func windowDidResignKey(_ n: Notification) { panel.orderOut(nil) }

    func controlTextDidChange(_ n: Notification) { filter() }

    // Esc closes.
    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { panel.orderOut(nil); return true }
        return false
    }

    func numberOfRows(in t: NSTableView) -> Int { rows.count }
    func tableView(_ t: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .rule = rows[row] { return 17 } else { return 32 }
    }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSView()
        guard case .key(let h) = rows[row] else {
            // Draw the group break once, in the first column, spanning the full width.
            guard col?.identifier.rawValue == "keys" else { return cell }
            let r = hairline(); cell.addSubview(r)
            NSLayoutConstraint.activate([r.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                         r.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                                         r.widthAnchor.constraint(equalToConstant: 680)])
            return cell
        }
        let l: NSTextField
        switch col?.identifier.rawValue {
        case "keys": l = label(h.keys, mono(13, bold: true))
        case "name": l = label(h.name, sans(14))
        default:     l = label(h.spelled, mono(12), .secondaryLabelColor)
        }
        cell.addSubview(l)
        NSLayoutConstraint.activate([l.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     l.leadingAnchor.constraint(equalTo: cell.leadingAnchor)])
        return cell
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
