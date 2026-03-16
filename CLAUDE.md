# swift-sdk/CLAUDE.md

Swift SDK for Para wallet infrastructure (iOS).

## Build Commands

> **Note:** The Xcode workspace (`ParaSwift.xcworkspace`) lives in the parent directory. It includes both `swift-sdk` and the example apps.

### Build the Swift package

```bash
xcodebuild \
  -workspace ../ParaSwift.xcworkspace \
  -scheme ParaSwift \
  -sdk iphonesimulator \
  -configuration Release \
  build
```

### Format and Lint

```bash
swiftformat --swiftversion 6.1 .
```
> Run `swiftformat` before committing.

## E2E Tests
> Note: There are no unit tests for swift-sdk. E2E tests are preferred (see below).

> **Location:**
> All E2E/XCTest UI tests live in the sibling `examples-hub` repo under
> `examples-hub/mobile/with-swift/exampleUITests`.

To run them from the parent workspace:

1. **Run every E2E test**
   ```bash
   xcodebuild \
     -workspace ../ParaSwift.xcworkspace \
     -scheme Example \
     -sdk iphonesimulator \
     -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
     test
   ```

2. **Run a single E2E test method**
   ```bash
   xcodebuild \
     -workspace ../ParaSwift.xcworkspace \
     -scheme Example \
     -sdk iphonesimulator \
     -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
     test \
     -only-testing:exampleUITests/ExampleUITests/<testMethodName>
   ```

## Code Guidelines
- Swift tools version: 5.10 (see Package.swift for current target)
- Platform support: iOS only (no macOS, watchOS, or tvOS support needed)
- Follow Swift API Design Guidelines (https://swift.org/documentation/api-design-guidelines/)
- Avoid force unwrapping (`!`) except in tests; use proper error handling in production code
- Error handling: Use structured `do/catch` blocks with specific error types
- Naming: camelCase for variables/functions, PascalCase for types/protocols
- Prefer Swift's modern concurrency (async/await) over completion handlers
- Standard indentation: 4 spaces
- Use strong types rather than Any/AnyObject
- Access control: private/fileprivate for implementation details, internal by default
- Documentation: Add doc comments to public APIs using Swift's documentation format
- Use SwiftUI for UI components
- For Objective-C interop, use proper `@objc` annotations when needed
- When working with async code, consider task cancellation and lifecycle management
