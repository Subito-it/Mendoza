//
//  SimulatorFramebuffer.swift
//  Mendoza
//
//  Created by Tomas Camin on 13/08/2026.
//

import CoreImage
import Foundation
import IOSurface

/// Read-only access to a booted simulator's screen via the private `SimulatorKit.framework`.
///
/// Xcode 27 replaced Simulator.app with DeviceHub, which only displays simulators it booted
/// itself and so never shows Mendoza's `simctl` booted ones (Apple known issue 176809181).
/// SimulatorKit however links CoreSimulator only, with no CoreDevice dependency, so its
/// framebuffer is reachable for any booted device regardless of who booted it.
///
/// Chain: `SimDevice` -> `SimDeviceScreen(device:screenID:)` -> `screen` -> `framebufferSurface`.
///
/// - Important: The `IOSurface` is shared GPU memory owned by the simulator, not a copy. Reading
///              it is cheap; only converting a frame to an image costs anything.
enum SimulatorFramebuffer {
    /// `screenID` 0 is not a valid screen, the built in display is 1.
    private static let integratedDisplayID: UInt32 = 1

    static func load(developerDir: String) -> Bool {
        // SimulatorKit moved to Contents/SharedFrameworks in Xcode 27, derive it from the
        // developer dir so the framework matches the Xcode being used.
        let xcodePath = developerDir.replacingOccurrences(of: "/Contents/Developer", with: "")
        let path = "\(xcodePath)/Contents/SharedFrameworks/SimulatorKit.framework"
        return Bundle(path: path)?.load() ?? false
    }

    /// The object rendering the device's built in display, or `nil` when unavailable.
    ///
    /// - Note: Requires a booted device.
    static func screen(for device: AnyObject) -> AnyObject? {
        guard let screenClass = NSClassFromString("_TtC12SimulatorKit15SimDeviceScreen") else { return nil }
        guard let allocated = (screenClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }

        let selector = NSSelectorFromString("initWithDevice:screenID:")
        guard let method = class_getInstanceMethod(screenClass, selector) else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> AnyObject?
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)

        guard let screen = function(allocated, selector, device, integratedDisplayID) else { return nil }
        return screen.perform(NSSelectorFromString("screen"))?.takeUnretainedValue()
    }

    static func surface(of screen: AnyObject) -> IOSurfaceRef? {
        guard let object = screen.perform(NSSelectorFromString("framebufferSurface"))?.takeUnretainedValue() else { return nil }
        return unsafeBitCast(object, to: IOSurfaceRef.self)
    }

    /// Monotonic counter bumped by the simulator whenever it writes a new frame.
    ///
    /// This is polled instead of registering an `ioSurfacesChangeCallback:`: a registered
    /// callback that outlives its process makes `SimRenderServer` raise
    /// `doesNotRecognizeSelector`, which kills the simulator's render server and takes the
    /// booted guest OS down with it. Polling cannot outlive the process.
    static func seed(of surface: IOSurfaceRef) -> UInt32 {
        IOSurfaceGetSeed(surface)
    }

    static func size(of surface: IOSurfaceRef) -> CGSize {
        CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
    }

    static func image(of surface: IOSurfaceRef, context: CIContext) -> CGImage? {
        IOSurfaceLock(surface, .readOnly, nil)
        let image = CIImage(ioSurface: surface)
        IOSurfaceUnlock(surface, .readOnly, nil)

        return context.createCGImage(image, from: image.extent)
    }
}
