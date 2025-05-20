import AppKit
import AccessibilityBridging
import CoreGraphics

public struct AXWindowID: Hashable, Sendable {
    public let windowNumber: CGWindowID
    public let processID: pid_t?
}

public extension AXWindow {
    
    var windowNumber: CGWindowID {
        var windowNumber: CGWindowID = 0
        _AXUIElementGetWindow(element, &windowNumber)
        return windowNumber
    }
    
    var processID: pid_t? {
        try? self.application?.pid()
    }
    
    var windowID: AXWindowID {
        .init(windowNumber: windowNumber, processID: processID)
    }
    
}
