@preconcurrency import Cocoa

public struct AnyAXElement: AXElement {
    public var element: AXUIElement

    public init(_ nativeElement: AXUIElement) {
        // Since we are dealing with low-level C APIs, it never hurts to double check types.
        assert(CFGetTypeID(nativeElement) == AXUIElementGetTypeID(),
               "nativeElement is not an AXUIElement")

        element = nativeElement
    }
}
