@preconcurrency import Cocoa

public struct FindFocusedWindowOptions: OptionSet, Sendable {
    public var rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let noSheets: Self = .init(rawValue: 1 << 0)
}

public struct AXWindow: AXElement {
    public let element: AXUIElement
    
    public init(_ nativeElement: AXUIElement) {
        assert(
            CFGetTypeID(nativeElement) == AXUIElementGetTypeID(),
            "nativeElement is not an AXUIElement"
        )
        element = nativeElement
    }
    
    public func getPosition() throws(AXError) -> CGPoint? {
        try self.attribute(.position, as: CGPoint.self)
    }
    
    public func getSize() throws(AXError) -> CGSize? {
        try self.attribute(.size, as: CGSize.self)
    }
    
    @MainActor
    public func set(position: CGPoint) throws(AXError) {
        try self.setAttribute(.position, value: position)
    }
    
    @MainActor
    public func set(size: CGSize) throws(AXError) {
        try self.setAttribute(.size, value: size)
    }
    
    public func getFrame() throws(AXError) -> CGRect? {
        guard let position = try self.getPosition(),
              let size = try self.getSize() else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
    
    public static func focusedWindow(
        options: [FindFocusedWindowOptions] = [.noSheets]
    ) throws(AXError) -> AXWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let application = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &window)
        if copyResult != AXError.success {
            return nil
        }
        let axuiElement = (window as! AXUIElement)
        guard options.contains(.noSheets) else {
            return AXWindow(axuiElement)
        }
        var uiElement = GenericAXElement(axuiElement)
        while (try? uiElement.role()) == .sheet {
            if let parentElement: GenericAXElement = try? uiElement.attribute(.parent) {
                uiElement = parentElement
            } else {
                return nil
            }
        }
        if (try? uiElement.role()) != .window {
            return nil
        }
        return AXWindow(uiElement.element)
    }
    
}
