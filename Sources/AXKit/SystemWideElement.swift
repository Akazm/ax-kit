@preconcurrency import Cocoa
import Foundation

/// A singleton for the system-wide element.
public let systemWideElement = SystemWideAXElement(AXUIElementCreateSystemWide())

public struct SystemWideAXElement: AXElement {
    public let element: AXUIElement

    public init(_ nativeElement: AXUIElement) {
        // Since we are dealing with low-level C APIs, it never hurts to double check types.
        assert(CFGetTypeID(nativeElement) == AXUIElementGetTypeID(),
               "nativeElement is not an AXUIElement")

        element = nativeElement
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
