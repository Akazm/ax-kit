import Cocoa
import Darwin
import Foundation
import Mutex

/// Observers watch for events on an application's UI elements.
///
/// Events are received as part of the application's default run loop.
///
/// - seeAlso: `UIElement` for a list of exceptions that can be thrown.
public final class AXKitObserver: Sendable {
    public typealias Callback = @Sendable (
        _ observer: AXKitObserver,
        _ element: AnyAXElement,
        _ notification: AXNotificationType
    ) async -> Void

    let pid: pid_t
    let callback: Callback
    nonisolated private let axObserver = Mutex<AXObserver?>(nil)

    /// Creates and starts an observer on the given `processID`.
    @MainActor
    public init(processID: pid_t, callback: @escaping Callback) throws {
        self.pid = processID
        try self.axObserver.withLock { selfAxObserver in
            var axObserver: AXObserver?
            let error = AXObserverCreate(processID, internalCallback, &axObserver)
            guard error == .success else {
                throw error
            }
            selfAxObserver = axObserver!
        }
        self.callback = callback
        start()
    }

    deinit {
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
    
    /// Starts watching for events. You don't need to call this method unless you use `stop()`.
    ///
    /// If the observer has already been started, this method does nothing.
    @MainActor
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
    @MainActor
    public func stop() {
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
    @MainActor
    public func addNotification(
        _ notification: AXNotificationType, forElement element: AnyAXElement
    ) throws {
        try axObserver.withLock { axObserver in
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
    @MainActor
    public func removeNotification(
        _ notification: AXNotificationType,
        forElement element: AnyAXElement
    ) throws {
        try axObserver.withLock { axObserver in
            guard let axObserver else {
                return
            }
            let result = AXObserverRemoveNotification(
                axObserver, element.element, notification.rawValue as CFString
            )
            guard result == .success || result == .notificationNotRegistered else {
                throw result
            }
        }
    }

}

private func internalCallback(
    _: AXObserver,
    axElement: AXUIElement,
    notification: CFString,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else {
        fatalError("userData should be an AXSwift.Observer")
    }
    let observer = Unmanaged<AXKitObserver>.fromOpaque(userData).takeUnretainedValue()
    let element = AnyAXElement(axElement)
    guard let notif = AXNotificationType(rawValue: notification as String) else {
        NSLog("Unknown AX notification %s received", notification as String)
        return
    }
    Task {
        await observer.callback(observer, element, notif)
    }
}
