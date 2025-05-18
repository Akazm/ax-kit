import Cocoa
import Darwin
import Foundation
import Mutex

public extension Sequence where Element == NSRunningApplication {
    
    func axObserver(
        _ callback: @escaping AXKitObserver<GenericAXElement>.Callback
    ) throws -> [AXKitObserver<GenericAXElement>] {
        try map {
            try AXKitObserver(processID: $0.processIdentifier, callback: callback)
        }
    }
    
}

/// Observers watch for events on an application's UI elements.
///
/// Events are received as part of the application's default run loop.
///
/// - seeAlso: `UIElement` for a list of exceptions that can be thrown.
public final class AXKitObserver<E: AXElement>: Sendable {
    public typealias Callback = @Sendable (
        _ observer: AXKitObserver,
        _ element: E,
        _ notification: AXNotification,
        _ info: [String: AnyObject]?
    ) -> Void

    let pid: pid_t
    let axObserver: Mutex<(AXObserver)?> = .init(nil)
    let callback: Callback

    /// Creates and starts an observer on the given `processID`.
    public init(processID: pid_t, callback: @escaping Callback) throws {
        self.pid = processID
        try self.axObserver.withLock {
            var axObserver: AXObserver?
            let error = AXObserverCreateWithInfoCallback(processID, internalCallback, &axObserver)
            guard error == .success else {
                throw error
            }
            $0 = axObserver
        }
        self.callback = callback
        start()
    }

    deinit {
        stop()
    }

    /// Starts watching for events. You don't need to call this method unless you use `stop()`.
    ///
    /// If the observer has already been started, this method does nothing.
    public func start() {
        axObserver.withLock { axObserver in
            guard let axObserver else {
                return
            }
            CFRunLoopAddSource(
                RunLoop.current.getCFRunLoop(),
                AXObserverGetRunLoopSource(axObserver),
                CFRunLoopMode.defaultMode
            )
        }
    }

    /// Stops sending events to your callback until the next call to `start`.
    ///
    /// If the observer has already been started, this method does nothing.
    ///
    /// - important: Events will still be queued in the target process until the Observer is started
    ///              again or destroyed. If you don't want them, create a new Observer.
    public func stop() {
        axObserver.withLock { axObserver in
            guard let axObserver else {
                return
            }
            CFRunLoopRemoveSource(
                RunLoop.current.getCFRunLoop(),
                AXObserverGetRunLoopSource(axObserver),
                CFRunLoopMode.defaultMode
            )
        }
    }

    /// Adds a notification for the observer to watch.
    ///
    /// - parameter notification: The name of the notification to watch for.
    /// - parameter forElement: The element to watch for the notification on. Must belong to the
    ///                         application this observer was created on.
    /// - seeAlso: [Notificatons](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/c/data/NSAccessibilityAnnouncementRequestedNotification)
    /// - note: The underlying API returns an error if the notification is already added, but that
    ///         error is not passed on for consistency with `start()` and `stop()`.
    /// - throws: `Error.NotificationUnsupported`: The element does not support notifications (note
    ///           that the system-wide element does not support notifications).
    public func addNotification<Element: AXElement>(
        _ notification: AXNotification, forElement element: Element
    ) throws {
        try axObserver.withLock { @Sendable axObserver in
            guard let axObserver else {
                return
            }
            let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let result = AXObserverAddNotification(
                axObserver, element.element, notification.rawValue as CFString, selfPtr
            )
            guard result == .success || result == .notificationAlreadyRegistered else {
                throw result
            }
        }
    }

    /// Removes a notification from the observer.
    ///
    /// - parameter notification: The name of the notification to stop watching.
    /// - parameter forElement: The element to stop watching the notification on.
    /// - note: The underlying API returns an error if the notification is not present, but that
    ///         error is not passed on for consistency with `start()` and `stop()`.
    /// - throws: `Error.NotificationUnsupported`: The element does not support notifications (note
    ///           that the system-wide element does not support notifications).
    public func removeNotification<Element: AXElement>(
        _ notification: AXNotification,
        forElement element: Element
    ) throws {
        let result = axObserver.withLock { axObserver -> AXError? in
            guard let axObserver else {
                return nil
            }
            return AXObserverRemoveNotification(
                axObserver, element.element, notification.rawValue as CFString
            )
        }
        guard let result else {
            return
        }
        guard result == .success || result == .notificationNotRegistered else {
            throw result
        }
    }
}

private func internalCallback(
    _: AXObserver,
    axElement: AXUIElement,
    notification: CFString,
    cfInfo: CFDictionary,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else {
        fatalError("userData should be an AXSwift.Observer")
    }
    let observer = Unmanaged<AXKitObserver<GenericAXElement>>.fromOpaque(userData).takeUnretainedValue()
    let element = GenericAXElement(axElement)
    guard let notif = AXNotification(rawValue: notification as String) else {
        NSLog("Unknown AX notification %s received", notification as String)
        return
    }
    if let info = cfInfo as NSDictionary? as? [String: AnyObject] {
        observer.callback(observer, element, notif, info)
    } else {
        observer.callback(observer, element, notif, nil)
    }
}
