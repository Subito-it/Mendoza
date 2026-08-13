//
//  SimulatorWindows.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/08/2026.
//

import AppKit
import CoreImage
import Foundation

/// Shows every booted simulator in its own window, tiled in a grid.
///
/// Exists because DeviceHub, which replaced Simulator.app in Xcode 27, only displays simulators
/// it booted itself and so never shows the ones Mendoza boots via `simctl`. See
/// `SimulatorFramebuffer` for how the screen contents are obtained.
///
/// Display only: no touch or keyboard events are ever sent, so this cannot interfere with a
/// running test session.
final class SimulatorWindows: NSObject, NSApplicationDelegate {
    private final class ScreenView: NSView {
        private let context = CIContext(options: [.useSoftwareRenderer: false])
        private let screen: AnyObject
        private var lastSeed: UInt32?

        init(screen: AnyObject, frame: NSRect) {
            self.screen = screen
            super.init(frame: frame)
            wantsLayer = true
            layer?.contentsGravity = .resizeAspect
            layer?.backgroundColor = NSColor.black.cgColor
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        func refresh() {
            guard let surface = SimulatorFramebuffer.surface(of: screen) else { return }

            let seed = SimulatorFramebuffer.seed(of: surface)
            guard seed != lastSeed else { return }
            lastSeed = seed

            if let image = SimulatorFramebuffer.image(of: surface, context: context) {
                layer?.contents = image
            }
        }
    }

    private let developerDir: String
    private let framesPerSecond: Double
    private let scale: CGFloat
    private var views = [ScreenView]()
    private var windows = [NSWindow]()
    private var timer: Timer?
    private var interruptSource: DispatchSourceSignal?

    init(developerDir: String, framesPerSecond: Double, scale: CGFloat) {
        self.developerDir = developerDir
        self.framesPerSecond = framesPerSecond
        self.scale = scale
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard SimulatorFramebuffer.load(developerDir: developerDir) else {
            print("Failed loading SimulatorKit from \(developerDir)")
            NSApp.terminate(nil)
            return
        }

        let booted = CoreSimulatorProxy.devices(developerDir: developerDir).filter { CoreSimulatorProxy.isBooted($0) }
        guard !booted.isEmpty else {
            print("No booted simulators")
            NSApp.terminate(nil)
            return
        }

        for (index, device) in booted.enumerated() {
            guard let screen = SimulatorFramebuffer.screen(for: device),
                  let surface = SimulatorFramebuffer.surface(of: screen)
            else {
                print("\(CoreSimulatorProxy.name(of: device) ?? "?"): no framebuffer available")
                continue
            }

            let pixels = SimulatorFramebuffer.size(of: surface)
            let size = NSSize(width: pixels.width / scale, height: pixels.height / scale)
            let view = ScreenView(screen: screen, frame: NSRect(origin: .zero, size: size))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = CoreSimulatorProxy.name(of: device) ?? "Simulator"
            window.contentView = view
            window.setFrameOrigin(origin(index: index, size: size))
            window.makeKeyAndOrderFront(nil)

            view.refresh()
            views.append(view)
            windows.append(window)

            print("\(window.title) \(CoreSimulatorProxy.identifier(of: device) ?? "")")
        }

        guard !views.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / framesPerSecond, repeats: true) { [weak self] _ in
            self?.views.forEach { $0.refresh() }
        }

        installInterruptHandler()
    }

    /// `NSApplication.run()` swallows SIGINT, so without this Ctrl-C would leave the windows
    /// and the process behind.
    private func installInterruptHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        interruptSource = source
        signal(SIGINT, SIG_IGN)
    }

    private func origin(index: Int, size: NSSize) -> NSPoint {
        let perRow = 3
        let margin: CGFloat = 20
        let column = index % perRow
        let row = index / perRow

        guard let visible = NSScreen.main?.visibleFrame else {
            return NSPoint(x: margin, y: margin)
        }

        let x = visible.minX + margin + (size.width + margin) * CGFloat(column)
        let y = visible.maxY - size.height - margin - (size.height + margin) * CGFloat(row)

        return NSPoint(x: x, y: y)
    }
}
