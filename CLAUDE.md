# swift-sdk/CLAUDE.md

Swift SDK for Para wallet infrastructure (iOS).

## Build Commands

> **Note:** The main Xcode workspace lives one level above this folder at `~/para/Para.xcworkspace`. That workspace includes both `swift-sdk` and the example apps (`examples-hub`).

### Build the Swift package for iOS 16.5

```bash
cd ~/para
xcodebuild \
  -workspace ParaSwift.xcworkspace \
  -scheme ParaSwift \
  -sdk iphonesimulator \
  -configuration Release \
  build
```

### Format and Lint

```bash
cd ~/para/swift-sdk
swiftformat --swiftversion 6.1 .
```
> Run `swiftformat` before committing.

## E2E Tests
> Note: There are no unit tests for swift-sdk. E2E tests are preferred (see below).

> **Location:**  
> All E2E/XCTest UI tests for the iOS example app live under
> `~/para/examples-hub/mobile/with-swift/exampleUITests`.

To run them from the root workspace:

1. **Run every E2E test**  
   ```bash
   cd ~/para
   xcodebuild \
     -workspace ParaSwift.xcworkspace \
     -scheme Example \
     -sdk iphonesimulator \
     -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
     test
   ```

2. **Run a single E2E test method**  
   ```bash
   cd ~/para
   xcodebuild \
     -workspace ParaSwift.xcworkspace \
     -scheme Example \
     -sdk iphonesimulator \
     -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
     test \
     -only-testing:exampleUITests/ExampleUITests/<testMethodName>
   ```

## Code Guidelines
- Swift version: 6.10+
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
