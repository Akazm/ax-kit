# AXKit

AXKit (forked from AXSwift) is a Swift wrapper for macOS's C-based accessibility client APIs. Working with these APIs is
error-prone and a huge pain, so AXKit makes everything easier:

- Modern API that's 100% Swift
- Explicit error handling
- Complete coverage of the underlying C API
- Better documentation than Apple's, which is pretty poor

This framework is intended as a basic wrapper, and doesn't keep any state or do any "magic".
That's up to you!

## Using AXKit

### SPM
In your Package.swift:
```
.package(url: "https://github.com/akazm/ax-kit", from: "1.0.0"),
```

### Documentation

[View auto-generated SwiftDoc](https://akazm.github.io/ax-kit/documentation/axkit/)

See the source of [AXKitExample](https://github.com/akazm/ax-kit/blob/master/AXKitExample/AppDelegate.swift)
and [AXKitObserverExample](https://github.com/akazm/ax-kit/blob/master/AXKitObserverExample/AppDelegate.swift)
for an example of the API.
