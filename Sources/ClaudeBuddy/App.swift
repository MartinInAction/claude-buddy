import AppKit
import SwiftUI

@main
struct ClaudeBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SessionModel.shared

    var body: some Scene {
        MenuBarExtra {
            Text(model.lastEventDescription).font(.caption)
            Text("\(model.eventCount) events · \(model.agents.count) characters").font(.caption2).foregroundStyle(.secondary)
            Divider()
            Text("₿ \(Miner.format(model.miner.total)) mined" + (model.miner.isMining ? " · mining now" : "")).font(.caption)
            Divider()
            Button(delegate.panelVisible ? "Hide Buddy" : "Show Buddy") { delegate.toggle() }
                .keyboardShortcut("b")
            Toggle("Hot corner (bottom right)", isOn: Binding(get: { delegate.hotCorner }, set: { delegate.hotCorner = $0 }))
            Button("Reset position") { delegate.panel?.resetPosition() }
            Button("Play demo") { model.demo() }
            Button("Do a trick") { model.trick() }
            Button("Clear characters") { model.clear() }
            Divider()
            Picker("Context window", selection: Binding(
                get: { ContextMeter.window },
                set: { ContextMeter.window = $0 })) {
                Text("200k").tag(200_000)
                Text("1M").tag(1_000_000)
            }
            Text("Listening on 127.0.0.1:\(String(EventServer.defaultPort))").font(.caption2).foregroundStyle(.secondary)
            Button("Quit Claude Buddy") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "figure.wave")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var panel: BuddyPanel?
    private var server: EventServer?
    @Published var panelVisible = true
    /// Hot-corner mode: the buddy stays faded out until the mouse hits the bottom-right corner of its screen,
    /// hovers over it, or a character needs input.
    @Published var hotCorner = UserDefaults.standard.bool(forKey: "hotCorner") {
        didSet { UserDefaults.standard.set(hotCorner, forKey: "hotCorner"); if !hotCorner { setShown(true) } }
    }
    private var poll: Timer?
    private var revealedUntil = Date.distantPast
    private var shown = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panel = BuddyPanel()
        let root = BuddyStrip(model: SessionModel.shared) { [weak panel] size in
            panel?.resize(to: size)
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.placeInitially()
        panel.orderFrontRegardless()
        self.panel = panel

        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollHotCorner() }
        }

        do {
            server = try EventServer { [weak self] path, data in
                if path.hasPrefix("/snapshot") {
                    // Debug helper: POST /snapshot {"path": "/tmp/x.png"} renders the panel to a PNG.
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let out = obj?["path"] as? String { Task { @MainActor in self?.snapshot(to: out) } }
                    return
                }
                guard let event = BuddyEvent(json: data) else { return }
                Task { @MainActor in SessionModel.shared.handle(event) }
            }
        } catch {
            NSLog("ClaudeBuddy: could not start server: \(error)")
        }
    }

    func snapshot(to path: String) {
        guard let view = panel?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func toggle() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless(); if !hotCorner { setShown(true) } }
        panelVisible = panel.isVisible
    }

    // MARK: - Hot corner

    private func pollHotCorner() {
        guard hotCorner, panelVisible, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let corner = CGPoint(x: screen.frame.maxX, y: screen.frame.minY)
        let inCorner = abs(mouse.x - corner.x) <= 8 && abs(mouse.y - corner.y) <= 8
        let overPanel = shown && panel.frame.insetBy(dx: -24, dy: -24).contains(mouse)
        let needsInput = SessionModel.shared.agents.contains { $0.needsInput }
        let now = Date()
        if inCorner || overPanel || needsInput { revealedUntil = now.addingTimeInterval(1.5) }
        setShown(now < revealedUntil)
    }

    private func setShown(_ on: Bool) {
        guard on != shown, let panel else { return }
        shown = on
        panel.ignoresMouseEvents = !on
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = on ? 0.2 : 0.4
            panel.animator().alphaValue = on ? 1 : 0
        }
    }
}
