@preconcurrency import Cocoa

/// A `UIElement` for an application.
public struct AXApplication: AXElement {
    public let element: AXUIElement

    public init(_ nativeElement: AXUIElement) {
        assert(
            CFGetTypeID(nativeElement) == AXUIElementGetTypeID(),
            "nativeElement is not an AXUIElement"
        )
        element = nativeElement
    }

    // Creates a UIElement for the given process ID.
    // Does NOT check if the given process actually exists, just checks for a valid ID.
    init?(forKnownProcessID processID: pid_t) {
        let appElement = AXUIElementCreateApplication(processID)
        self.init(appElement)

        if processID < 0 {
            return nil
        }
    }

    /// Creates an `Application` from a `NSRunningApplication` instance.
    /// - returns: The `Application`, or `nil` if the given application is not running.
    public init?(_ app: NSRunningApplication) {
        if app.isTerminated {
            return nil
        }
        self.init(forKnownProcessID: app.processIdentifier)
    }

    /// Create an `Application` from the process ID of a running application.
    /// - returns: The `Application`, or `nil` if the PID is invalid or the given application
    ///            is not running.
    public init?(forProcessID processID: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: processID) else {
            return nil
        }
        self.init(app)
    }

    /// Creates an `Application` for every running application with a UI.
    /// - returns: An array of `Application`s.
    public static func all() -> [AXApplication] {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps
            .filter { $0.activationPolicy != .prohibited }
            .compactMap { AXApplication($0) }
    }

    /// Creates an `Application` for every running instance of the given `bundleID`.
    /// - returns: A (potentially empty) array of `Application`s.
    public static func allForBundleID(_ bundleID: String) -> [AXApplication] {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps
            .filter { $0.bundleIdentifier == bundleID }
            .compactMap { AXApplication($0) }
    }

    /// Creates an `Observer` on this application, if it is still alive.
    @MainActor
    public func createObserver(_ callback: @escaping AXKitObserver.Callback) -> AXKitObserver? {
        do {
            return try AXKitObserver(processID: pid(), callback: callback)
        } catch AXError.invalidUIElement {
            return nil
        } catch {
            fatalError("Caught unexpected error creating observer: \(error)")
        }
    }

    /// Returns a list of the application's visible windows.
    /// - returns: An array of `UIElement`s, one for every visible window. Or `nil` if the list
    ///            cannot be retrieved.
    public func windows() throws -> [AXWindow]? {
        let axWindows: [AXUIElement]? = try attribute("AXWindows")
        return axWindows?.map { AXWindow($0) }
    }
    
    public func elementAtPosition(_ x: Float, _ y: Float) throws(AXError) -> AnyAXElement? {
        var result: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(element, x, y, &result)
        if error == .noValue {
            return nil as AnyAXElement?
        }
        guard error == .success else {
            throw error
        }
        return AnyAXElement(result!)
    }
    
}
