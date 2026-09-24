import AppKit
import Carbon

enum DrawingTool: String { case arrow = "Arrow", box = "Box" }
struct Mark {
    let tool: DrawingTool
    let start: NSPoint
    var end: NSPoint
    var distance: CGFloat { hypot(end.x - start.x, end.y - start.y) }
    var rect: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    var arrowWings: [NSPoint] {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = min(19, distance * 0.45)
        return [-CGFloat.pi / 6, CGFloat.pi / 6].map {
            NSPoint(x: end.x - length * cos(angle + $0), y: end.y - length * sin(angle + $0))
        }
    }
}

final class Overlay: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Canvas: NSView {
    weak var controller: AppDelegate?
    var marks: [(Int, Mark)] = []
    var pending: Mark?
    let hint = NSTextField(labelWithString: "")
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, controller: AppDelegate) {
        self.controller = controller
        super.init(frame: frame)
        let bar = NSVisualEffectView()
        bar.material = .hudWindow
        bar.blendingMode = .behindWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 12
        bar.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (title, action) in [("Arrow · A", #selector(AppDelegate.arrow)),
                                 ("Box · B", #selector(AppDelegate.box)),
                                 ("Undo · ⌘Z", #selector(AppDelegate.undo)),
                                 ("Clear · ⌫", #selector(AppDelegate.clear)),
                                 ("Done · Esc", #selector(AppDelegate.finish))] {
            let button = NSButton(title: title, target: controller, action: action)
            button.bezelStyle = .rounded
            stack.addArrangedSubview(button)
        }
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        bar.addSubview(stack)
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -36),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -12)
        ])
        updateHint()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func updateHint() { hint.stringValue = "\(controller?.tool.rawValue ?? "Arrow") selected" }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        pending = Mark(tool: controller?.tool ?? .arrow, start: point, end: point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard var mark = pending else { return }
        mark.end = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.shift) {
            let dx = mark.end.x - mark.start.x, dy = mark.end.y - mark.start.y
            if mark.tool == .box {
                let side = max(abs(dx), abs(dy))
                mark.end = NSPoint(x: mark.start.x + (dx < 0 ? -side : side),
                                   y: mark.start.y + (dy < 0 ? -side : side))
            } else {
                let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                let length = hypot(dx, dy)
                mark.end = NSPoint(x: mark.start.x + cos(angle) * length,
                                   y: mark.start.y + sin(angle) * length)
            }
        }
        pending = mark
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if let mark = pending, mark.distance > 3, let controller = controller {
            controller.sequence += 1
            marks.append((controller.sequence, mark))
        }
        pending = nil
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.finish()
        case 51, 117: controller?.clear()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": controller?.arrow()
            case "b", "r": controller?.box()
            case "z" where event.modifierFlags.contains(.command): controller?.undo()
            default: break
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        // WindowServer lets clicks pass through fully transparent pixels.
        // Keep a barely visible surface across the entire drawing area.
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill(using: .copy)
        for mark in marks.map({ $0.1 }) + (pending.map { [$0] } ?? []) {
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if mark.tool == .box {
                path.appendRect(mark.rect)
            } else {
                path.move(to: mark.start)
                path.line(to: mark.end)
                for wing in mark.arrowWings {
                    path.move(to: wing)
                    path.line(to: mark.end)
                }
            }
            NSColor.black.withAlphaComponent(0.65).setStroke()
            path.lineWidth = 6
            path.stroke()
            NSColor(calibratedRed: 1, green: 0.30, blue: 0.22, alpha: 1).setStroke()
            path.lineWidth = 3.5
            path.stroke()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var panels: [Overlay] = []
    var tool: DrawingTool = .arrow
    var sequence = 0
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var drawing = false
    var previousApp: NSRunningApplication?
    var canvases: [Canvas] { panels.compactMap { $0.contentView as? Canvas } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "Draw"
        status.button?.toolTip = "QuickDraw — Control Option D"
        let menu = NSMenu()
        for (title, action) in [("Toggle Drawing    ⌃⌥D", #selector(toggle)),
                                 ("Arrow    A", #selector(arrow)),
                                 ("Box    B", #selector(box)),
                                 ("Clear Drawings", #selector(clear)),
                                 ("Quit QuickDraw", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        status.menu = menu
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data = data else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            delegate.toggle()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey),
                                        EventHotKeyID(signature: 0x51445257, id: 1),
                                        GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr {
            let alert = NSAlert()
            alert.messageText = "QuickDraw's shortcut is unavailable"
            alert.informativeText = "Another app may use Control–Option–D. You can still start drawing from the Draw menu."
            alert.runModal()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        toggle()
    }
    @objc func screensChanged() { if drawing { finish() } }
    @objc func toggle() {
        if drawing { finish(); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        drawing = true
        status.button?.title = "Draw •"
        for screen in NSScreen.screens {
            let panel = Overlay(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = false
            panel.isFloatingPanel = true
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let canvas = Canvas(frame: NSRect(origin: .zero, size: screen.frame.size), controller: self)
            panel.contentView = canvas
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) {
                panel.makeKey()
                panel.makeFirstResponder(canvas)
            }
        }
    }
    @objc func finish() {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        drawing = false
        status.button?.title = "Draw"
        previousApp?.activate(options: [])
        previousApp = nil
    }
    @objc func arrow() { tool = .arrow; canvases.forEach { $0.updateHint() } }
    @objc func box() { tool = .box; canvases.forEach { $0.updateHint() } }
    @objc func clear() { canvases.forEach { $0.marks.removeAll(); $0.pending = nil; $0.needsDisplay = true } }
    @objc func undo() {
        guard let canvas = canvases.filter({ !$0.marks.isEmpty }).max(by: {
            $0.marks.last!.0 < $1.marks.last!.0
        }) else { return }
        canvas.marks.removeLast()
        canvas.needsDisplay = true
    }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--self-test") {
    let reverseBox = Mark(tool: .box, start: NSPoint(x: 100, y: 80), end: NSPoint(x: 20, y: 10))
    precondition(reverseBox.rect == NSRect(x: 20, y: 10, width: 80, height: 70))
    for endpoint in [NSPoint(x: 100, y: 0), NSPoint(x: -100, y: 0), NSPoint(x: 0, y: 100), NSPoint(x: 0, y: -100), .zero] {
        let mark = Mark(tool: .arrow, start: .zero, end: endpoint)
        for wing in mark.arrowWings {
            precondition(wing.x.isFinite && wing.y.isFinite)
            precondition(hypot(wing.x - endpoint.x, wing.y - endpoint.y) <= 19.001)
        }
    }
    print("PASS: reversed box bounds; arrow geometry in all directions and zero-length strokes")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
