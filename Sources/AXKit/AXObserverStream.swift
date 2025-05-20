import AppKit

public extension AXKitObserver {
    
    /// A sequence of accessibility events from an observer.
    struct EventSequence: AsyncSequence, Sendable {
        public typealias Element = (observer: AXKitObserver, element: AnyAXElement, type: AXNotificationType)
        
        private let processID: pid_t
        private let notifications: [AXNotificationType]
        
        public init(processID: pid_t, notifications: [AXNotificationType]) {
            self.processID = processID
            self.notifications = notifications
        }
        
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(processID: processID, notifications: notifications)
        }
        
        public struct AsyncIterator: AsyncIteratorProtocol  {
            private let processID: pid_t
            private var observer: AXKitObserver?
            private var iterator: AsyncThrowingStream<Element, Error>.AsyncIterator?
            private let notifications: [AXNotificationType]
            
            init(processID: pid_t, notifications: [AXNotificationType]) {
                self.processID = processID
                self.notifications = notifications
            }
            
            public mutating func next() async throws -> Element? {
                if iterator == nil {
                    let (stream, continuation) = AsyncThrowingStream<Element, Error>.makeStream()
                    self.iterator = stream.makeAsyncIterator()
                    do {
                        let observer = try await Task { [notifications, processID] in
                            let observer = try await AXKitObserver(processID: processID) { observer, element, notification in
                                continuation.yield((observer, element, notification))
                            }
                            guard let application = AXApplication(forProcessID: processID)?.eraseToAny() else {
                                return observer
                            }
                            for notification in notifications {
                                try await observer
                                    .addNotification(
                                        notification,
                                        forElement: application
                                    )
                            }
                            return observer
                        }.value
                        continuation.onTermination = { @Sendable _ in
                            Task { @MainActor [weak observer] in
                                observer?.stop()
                            }
                        }
                        self.observer = observer
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                return try await iterator?.next()
            }
        }
    }

    /// Creates an async sequence of accessibility events for the given process ID.
    ///
    /// - Parameter processID: The process ID to observe
    /// - Returns: An async sequence that yields tuples of (observer, element, notification)
    /// - Note: The sequence must be consumed on the main actor since it interacts with the accessibility API
    @MainActor
    static func stream(processID: pid_t, notifications: [AXNotificationType]) -> EventSequence {
        EventSequence(processID: processID, notifications: notifications)
    }
    
}