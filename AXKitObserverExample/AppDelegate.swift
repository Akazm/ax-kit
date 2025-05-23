import AXKit
import Cocoa
import Mutex

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_: Notification) {
        let app = AXApplication.allForBundleID("com.apple.finder").first!

        do {
            try startWatcher(app)
        } catch {
            NSLog("Error: Could not watch app [\(app)]: \(error)")
            abort()
        }
    }

    @MainActor
    func startWatcher(_ app: AXApplication) throws {
        let updated: Mutex<Bool> = .init(false)
        let stream = AXKitObserver.stream(processID: try app.pid(), notifications: [.windowCreated, .mainWindowChanged])
        Task {
            for try await (observer, element, event) in stream {
                var elementDesc: String!
                if let role = try? element.role(), role == .window {
                    elementDesc = "\(element) \"\(try! (element.attribute(.title) as String?)!)\""
                } else {
                    elementDesc = "\(element)"
                }
                print("\(event) on \(String(describing: elementDesc))")

                // Watch events on new windows
                if event == .windowCreated {
                    do {
                        try observer.addNotification(.uiElementDestroyed, forElement: element)
                        try observer.addNotification(.moved, forElement: element)
                    } catch {
                        NSLog("Error: Could not watch [\(element)]: \(error)")
                    }
                }

                // Group simultaneous events together with --- lines
                if !updated.withLock({ $0 }) {
                    updated.withLock { $0 = true }
                    // Set this code to run after the current run loop, which is dispatching all notifications.
                    DispatchQueue.main.async {
                        print("---")
                        updated.withLock { $0 = false }
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }
}
