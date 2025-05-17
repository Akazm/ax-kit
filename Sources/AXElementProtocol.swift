@preconcurrency import Cocoa
import Foundation

/// Holds and interacts with any accessibility element.
///
/// This class wraps every operation that operates on AXUIElements.
///
/// - seeAlso: [OS X Accessibility Model](https://developer.apple.com/library/mac/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html)
///
/// Note that every operation involves IPC and is tied to the event loop of the target process. This
/// means that operations are synchronous and can hang until they time out. The default timeout is
/// 6 seconds, but it can be changed using `setMessagingTimeout` and `setGlobalMessagingTimeout`.
///
/// Every attribute- or action-related function has an enum version and a String version. This is
/// because certain processes might report attributes or actions not documented in the standard API.
/// These will be ignored by enum functions (and you can't specify them). Most users will want to
/// use the enum-based versions, but if you want to be exhaustive or use non-standard attributes and
/// actions, you can use the String versions.
///
/// ### Error handling
///
/// Unless otherwise specified, during reads, "missing data/attribute" errors are handled by
/// returning optionals as nil. During writes, missing attribute errors are thrown.
///
/// Other failures are all thrown, including if messaging fails or the underlying AXUIElement
/// becomes invalid.
///
/// #### Possible Errors
/// - `Error.APIDisabled`: The accessibility API is disabled. Your application must request and
///                        receive special permission from the user to be able to use these APIs.
/// - `Error.InvalidUIElement`: The UI element has become invalid, perhaps because it was destroyed.
/// - `Error.CannotComplete`: There is a problem with messaging, perhaps because the application is
///                           being unresponsive. This error will be thrown when a message times
///                           out.
/// - `Error.NotImplemented`: The process does not fully support the accessibility API.
/// - Anything included in the docs of the method you are calling.
///
/// Any undocumented errors thrown are bugs and should be reported.
///
/// - seeAlso: [AXUIElement.h reference](https://developer.apple.com/library/mac/documentation/ApplicationServices/Reference/AXUIElement_header_reference/)
public protocol AXElement: Sendable, CustomStringConvertible, Equatable {
    var element: AXUIElement { get }
}

public extension AXElement {
    /// Checks if the current process is a trusted accessibility client. If false, all APIs will
    /// throw errors.
    ///
    /// - parameter withPrompt: Whether to show the user a prompt if the process is untrusted. This
    ///                         happens asynchronously and does not affect the return value.
    static func isProcessTrusted(withPrompt showPrompt: Bool = false) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showPrompt as CFBoolean,
        ]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Attributes

    /// Returns the list of all attributes.
    ///
    /// Does not include parameterized attributes.
    func attributes() throws(AXError) -> [Attribute] {
        let attrs = try attributesAsStrings()
        for attr in attrs where Attribute(rawValue: attr) == nil {
            print("Unrecognized attribute: \(attr)")
        }
        return attrs.compactMap { Attribute(rawValue: $0) }
    }

    // This version is named differently so the caller doesn't have to specify the return type when
    // using the enum version.
    func attributesAsStrings() throws(AXError) -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyAttributeNames(element, &names)

        if error == .noValue || error == .attributeUnsupported {
            return []
        }

        guard error == .success else {
            throw error
        }

        // We must first convert the CFArray to a native array, then downcast to an array of
        // strings.
        return names! as [AnyObject] as! [String]
    }

    /// Returns whether `attribute` is supported by this element.
    ///
    /// The `attribute` method returns nil for unsupported attributes and empty attributes alike,
    /// which is more convenient than dealing with exceptions (which are used for more serious
    /// errors). However, if you'd like to specifically test an attribute is actually supported, you
    /// can use this method.
    @MainActor
    func attributeIsSupported(_ attribute: Attribute) throws(AXError) -> Bool {
        try attributeIsSupported(attribute.rawValue)
    }

    @MainActor
    func attributeIsSupported(_ attribute: String) throws(AXError) -> Bool {
        // Ask to copy 0 values, since we are only interested in the return code.
        var value: CFArray?
        let error = AXUIElementCopyAttributeValues(element, attribute as CFString, 0, 0, &value)

        if error == .attributeUnsupported {
            return false
        }

        if error == .noValue {
            return true
        }

        guard error == .success else {
            throw error
        }

        return true
    }

    /// Returns whether `attribute` is writeable.
    @MainActor
    func attributeIsSettable(_ attribute: Attribute) throws(AXError) -> Bool {
        try attributeIsSettable(attribute.rawValue)
    }

    @MainActor
    func attributeIsSettable(_ attribute: String) throws(AXError) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)

        if error == .noValue || error == .attributeUnsupported {
            return false
        }

        guard error == .success else {
            throw error
        }

        return settable.boolValue
    }

    /// Returns the value of `attribute`, if it exists.
    ///
    /// - parameter attribute: The name of a (non-parameterized) attribute.
    ///
    /// - returns: An optional containing the value of `attribute` as the desired type, or nil.
    ///            If `attribute` is an array, all values are returned.
    ///
    /// - warning: This method force-casts the attribute to the desired type, which will abort if
    ///            the cast fails. If you want to check the return type, ask for Any.
    func attribute<T>(_ attribute: Attribute, as type: T.Type = T.self) throws(AXError) -> T? {
        try self.attribute(attribute.rawValue)
    }

    func attribute<T>(_ attribute: String, as type: T.Type = T.self) throws(AXError) -> T? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        if error == .noValue || error == .attributeUnsupported {
            return nil
        }

        guard error == .success else {
            throw error
        }

        guard let unpackedValue = (unpackAXValue(value!) as? T) else {
            throw AXError.illegalArgument
        }

        return unpackedValue
    }

    /// Sets the value of `attribute` to `value`.
    ///
    /// - warning: Unlike read-only methods, this method throws if the attribute doesn't exist.
    ///
    /// - throws:
    ///   - `Error.AttributeUnsupported`: `attribute` isn't supported.
    ///   - `Error.IllegalArgument`: `value` is an illegal value.
    ///   - `Error.Failure`: A temporary failure occurred.
    @MainActor
    func setAttribute(_ attribute: Attribute, value: Any) throws(AXError) {
        try setAttribute(attribute.rawValue, value: value)
    }

    @MainActor
    func setAttribute(_ attribute: String, value: Any) throws(AXError) {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, packAXValue(value))
        guard error == .success else {
            throw error
        }
    }

    /// Gets multiple attributes of the element at once.
    ///
    /// - parameter attributes: An array of attribute names. Nonexistent attributes are ignored.
    ///
    /// - returns: A dictionary mapping provided parameter names to their values. Parameters which
    ///            don't exist or have no value will be absent.
    ///
    /// - throws: If there are any errors other than .NoValue or .AttributeUnsupported, it will
    ///           throw the first one it encounters.
    ///
    /// - note: Presumably you would use this API for performance, though it's not explicitly
    ///         documented by Apple that there is actually a difference.
    func getMultipleAttributes(_ names: Attribute...) throws(AXError) -> [Attribute: Any] {
        try getMultipleAttributes(names)
    }

    func getMultipleAttributes(_ attributes: [Attribute]) throws(AXError) -> [Attribute: Any] {
        try packMultiAttrValues(attributes, values: fetchMultiAttrValues(attributes.map { $0.rawValue }))
    }

    func getMultipleAttributes(_ attributes: [String]) throws(AXError) -> [String: Any] {
        try packMultiAttrValues(attributes, values: fetchMultiAttrValues(attributes))
    }

    // Helper: Gets list of values
    fileprivate func fetchMultiAttrValues(_ attributes: [String]) throws(AXError) -> [AnyObject] {
        var valuesCF: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            // keep going on errors (particularly NoValue)
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &valuesCF
        )

        guard error == .success else {
            throw error
        }

        return valuesCF! as [AnyObject]
    }

    // Helper: Packs names, values into dictionary
    fileprivate func packMultiAttrValues<Attr>(
        _ attributes: [Attr], values: [AnyObject]
    ) throws(AXError) -> [Attr: Any] {
        var result = [Attr: Any]()
        for (index, attribute) in attributes.enumerated() {
            if try checkMultiAttrValue(values[index]) {
                result[attribute] = unpackAXValue(values[index])
            }
        }
        return result
    }

    // Helper: Checks if value is present and not an error (throws on nontrivial errors).
    fileprivate func checkMultiAttrValue(_ value: AnyObject) throws(AXError) -> Bool {
        // Check for null
        if value is NSNull {
            return false
        }

        // Check for error
        if CFGetTypeID(value) == AXValueGetTypeID() &&
            AXValueGetType(value as! AXValue).rawValue == kAXValueAXErrorType
        {
            var error = AXError.success
            AXValueGetValue(value as! AXValue, AXValueType(rawValue: kAXValueAXErrorType)!, &error)

            assert(error != .success)
            if error == .noValue || error == .attributeUnsupported {
                return false
            } else {
                throw error
            }
        }

        return true
    }

    // MARK: Array attributes

    /// Returns all the values of the attribute as an array of the given type.
    ///
    /// - parameter attribute: The name of the array attribute.
    ///
    /// - throws: `Error.IllegalArgument` if the attribute isn't an array.
    @MainActor
    func arrayAttribute<T>(_ attribute: Attribute, ofType _: T.Type = T.self) throws(AXError) -> [T]? {
        try arrayAttribute(attribute.rawValue)
    }

    @MainActor
    func arrayAttribute<T>(_ attribute: String, ofType _: T.Type = T.self) throws(AXError) -> [T]? {
        guard let value: Any = try self.attribute(attribute) else {
            return nil
        }
        guard let array = value as? [AnyObject] else {
            // For consistency with the other array attribute APIs, throw if it's not an array.
            throw AXError.illegalArgument
        }
        return array.map { unpackAXValue($0) as! T }
    }

    /// Returns a subset of values from an array attribute.
    ///
    /// - parameter attribute: The name of the array attribute.
    /// - parameter startAtIndex: The index of the array to start taking values from.
    /// - parameter maxValues: The maximum number of values you want.
    ///
    /// - returns: An array of up to `maxValues` values starting at `startAtIndex`.
    ///   - The array is empty if `startAtIndex` is out of range.
    ///   - `nil` if the attribute doesn't exist or has no value.
    ///
    /// - throws: `Error.IllegalArgument` if the attribute isn't an array.
    @MainActor
    func valuesForAttribute<T: AnyObject>(
        _ attribute: Attribute, startAtIndex index: Int, maxValues: Int, ofType _: T.Type = T.self
    ) throws(AXError) -> [T]? {
        return try valuesForAttribute(attribute.rawValue, startAtIndex: index, maxValues: maxValues)
    }

    @MainActor
    func valuesForAttribute<T: AnyObject>(
        _ attribute: String, startAtIndex index: Int, maxValues: Int, ofType _: T.Type = T.self
    ) throws(AXError) -> [T]? {
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(
            element, attribute as CFString, index, maxValues, &values
        )

        if error == .noValue || error == .attributeUnsupported {
            return nil
        }

        guard error == .success else {
            throw error
        }

        let array = values! as [AnyObject]
        return array.map { unpackAXValue($0) as! T }
    }

    /// Returns the number of values an array attribute has.
    /// - returns: The number of values, or `nil` if `attribute` isn't an array (or doesn't exist).
    @MainActor
    func valueCountForAttribute(_ attribute: Attribute) throws -> Int? {
        try valueCountForAttribute(attribute.rawValue)
    }

    @MainActor
    func valueCountForAttribute(_ attribute: String) throws(AXError) -> Int? {
        var count = 0
        let error = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)

        if error == .attributeUnsupported || error == .illegalArgument {
            return nil
        }

        guard error == .success else {
            throw error
        }

        return count
    }

    // MARK: Parameterized attributes

    /// Returns a list of all parameterized attributes of the element.
    ///
    /// Parameterized attributes are attributes that require parameters to retrieve. For example,
    /// the cell contents of a spreadsheet might require the row and column of the cell you want.
    @MainActor
    func parameterizedAttributes() throws(AXError) -> [Attribute] {
        try parameterizedAttributesAsStrings().compactMap { Attribute(rawValue: $0) }
    }

    @MainActor
    func parameterizedAttributesAsStrings() throws(AXError) -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyParameterizedAttributeNames(element, &names)

        if error == .noValue || error == .attributeUnsupported {
            return []
        }

        guard error == .success else {
            throw error
        }

        // We must first convert the CFArray to a native array, then downcast to an array of
        // strings.
        return names! as [AnyObject] as! [String]
    }

    /// Returns the value of the parameterized attribute `attribute` with parameter `param`.
    ///
    /// The expected type of `param` depends on the attribute. See the
    /// [NSAccessibility Informal Protocol Reference](https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Protocols/NSAccessibility_Protocol/)
    /// for more info.
    @MainActor
    func parameterizedAttribute<T, U>(_ attribute: Attribute, param: U) throws(AXError) -> T? {
        try parameterizedAttribute(attribute.rawValue, param: param)
    }

    @MainActor
    func parameterizedAttribute<T, U>(_ attribute: String, param: U) throws(AXError) -> T? {
        var value: AnyObject?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element, attribute as CFString, param as AnyObject, &value
        )

        if error == .noValue || error == .attributeUnsupported {
            return nil
        }

        guard error == .success else {
            throw error
        }

        return (unpackAXValue(value!) as! T)
    }

    // MARK: Attribute helpers

    // Checks if the value is an AXValue and if so, unwraps it.
    // If the value is an AXUIElement, wraps it in ``AnyUIElement``.
    fileprivate func unpackAXValue(_ value: AnyObject) -> Any {
        switch CFGetTypeID(value) {
            case AXUIElementGetTypeID():
                return GenericAXElement(value as! AXUIElement)
            case AXValueGetTypeID():
                let type = AXValueGetType(value as! AXValue)
                switch type {
                    case .axError:
                        var result: AXError = .success
                        let success = AXValueGetValue(value as! AXValue, type, &result)
                        assert(success)
                        return result
                    case .cfRange:
                        var result = CFRange()
                        let success = AXValueGetValue(value as! AXValue, type, &result)
                        assert(success)
                        return result
                    case .cgPoint:
                        var result = CGPoint.zero
                        let success = AXValueGetValue(value as! AXValue, type, &result)
                        assert(success)
                        return result
                    case .cgRect:
                        var result = CGRect.zero
                        let success = AXValueGetValue(value as! AXValue, type, &result)
                        assert(success)
                        return result
                    case .cgSize:
                        var result = CGSize.zero
                        let success = AXValueGetValue(value as! AXValue, type, &result)
                        assert(success)
                        return result
                    case .illegal:
                        return value
                    @unknown default:
                        return value
                }
            default:
                return value
        }
    }

    // Checks if the value is one supported by AXValue and if so, wraps it.
    // If the value is a UIElement, unwraps it to an AXUIElement.
    @MainActor
    fileprivate func packAXValue(_ value: Any) -> AnyObject {
        switch value {
            case let val as any AXElement:
                return val.element
            case var val as CFRange:
                return AXValueCreate(AXValueType(rawValue: kAXValueCFRangeType)!, &val)!
            case var val as CGPoint:
                return AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &val)!
            case var val as CGRect:
                return AXValueCreate(AXValueType(rawValue: kAXValueCGRectType)!, &val)!
            case var val as CGSize:
                return AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &val)!
            default:
                return value as AnyObject // must be an object to pass to AX
        }
    }

    // MARK: - Actions

    /// Returns a list of actions that can be performed on the element.
    func actions() throws -> [Action] {
        try actionsAsStrings().compactMap { Action(rawValue: $0) }
    }

    func actionsAsStrings() throws(AXError) -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)

        if error == .noValue || error == .attributeUnsupported {
            return []
        }

        guard error == .success else {
            throw error
        }

        // We must first convert the CFArray to a native array, then downcast to an array of strings.
        return names! as [AnyObject] as! [String]
    }

    /// Returns the human-readable description of `action`.
    func actionDescription(_ action: Action) throws(AXError) -> String? {
        try actionDescription(action.rawValue)
    }

    func actionDescription(_ action: String) throws(AXError) -> String? {
        var description: CFString?
        let error = AXUIElementCopyActionDescription(element, action as CFString, &description)
        if error == .noValue || error == .actionUnsupported {
            return nil
        }
        guard error == .success else {
            throw error
        }
        return description! as String
    }

    /// Performs the action `action` on the element, returning on success.
    ///
    /// - note: If the action times out, it might mean that the application is taking a long time to
    ///         actually perform the action. It doesn't necessarily mean that the action wasn't
    ///         performed.
    /// - throws: `Error.ActionUnsupported` if the action is not supported.
    func performAction(_ action: Action) throws(AXError) {
        try performAction(action.rawValue)
    }

    func performAction(_ action: String) throws(AXError) {
        let error = AXUIElementPerformAction(element, action as CFString)
        guard error == .success else {
            throw error
        }
    }

    // MARK: -

    /// Returns the process ID of the application that the element is a part of.
    ///
    /// Throws only if the element is invalid (`Errors.InvalidUIElement`).
    func pid() throws(AXError) -> pid_t {
        var pid: pid_t = -1
        let error = AXUIElementGetPid(element, &pid)

        guard error == .success else {
            throw error
        }

        return pid
    }

    /// Timeout in seconds for all UIElement messages. Use this to control how long a method call
    /// can delay execution. The default is `0` which means to use the system default.
    @MainActor
    static func setGlobalMessagingTimeout(_ messagingTimeout: Float) {
        systemWideElement.setMessagingTimeout(messagingTimeout)
    }

    /// The timeout in seconds for all messages sent to this element. Use this to control how long a
    /// method call can delay execution. The default is `0`, which means to use the global timeout.
    ///
    /// - note: Only applies to this instance of UIElement, not other instances that happen to equal
    ///         it.
    @MainActor
    func setMessagingTimeout(_ messagingTimeout: Float) {
        let messagingTimeout = max(messagingTimeout, 0)
        let error = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        // InvalidUIElement errors are only relevant when actually passing messages, so we can
        // ignore them here.
        guard error == .success || error == .invalidUIElement else {
            fatalError("Unexpected error setting messaging timeout: \(error)")
        }
    }

}

// MARK: - CustomStringConvertible

public extension AXElement {
    var description: String {
        var roleString: String
        var description: String?
        let pid = try? self.pid()
        do {
            let role = try self.role()
            roleString = role?.rawValue ?? "UIElementNoRole"

            switch role {
                case .some(.application):
                    description = pid
                        .flatMap { NSRunningApplication(processIdentifier: $0) }
                        .flatMap { $0.bundleIdentifier } ?? ""
                case .some(.window):
                    description = (try? attribute(.title) ?? "") ?? ""
                default:
                    break
            }
        } catch AXError.invalidUIElement {
            roleString = "InvalidUIElement"
        } catch {
            roleString = "UnknownUIElement"
        }

        let pidString = (pid == nil) ? "??" : String(pid!)
        return "<\(roleString) \""
            + "\(description ?? String(describing: element))"
            + "\" (pid=\(pidString))>"
    }

    var inspect: String {
        guard let attributeNames = try? attributes() else {
            return "InvalidUIElement"
        }
        guard let attributes = try? getMultipleAttributes(attributeNames) else {
            return "InvalidUIElement"
        }
        return "\(attributes)"
    }
}

// MARK: - Equatable

public extension AXElement {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return CFEqual(lhs.element, rhs.element)
    }
}

// MARK: - Convenience getters

public extension AXElement {
    /// Returns the role (type) of the element, if it reports one.
    ///
    /// Almost all elements report a role, but this could return nil for elements that aren't
    /// finished initializing.
    ///
    /// - seeAlso: [Roles](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/Roles)
    func role() throws -> Role? {
        // should this be non-optional?
        if let str: String = try attribute(.role) {
            return Role(rawValue: str)
        } else {
            return nil
        }
    }

    /// - seeAlso: [Subroles](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/Subroles)
    func subrole() throws -> Subrole? {
        if let str: String = try attribute(.subrole) {
            return Subrole(rawValue: str)
        } else {
            return nil
        }
    }
}
