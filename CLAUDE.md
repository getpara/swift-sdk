# swift-sdk/CLAUDE.md

Swift SDK for Para wallet infrastructure (iOS).

## Build Commands

### Build the Swift package

Run from the SDK directory. Inspect available schemes with `xcodebuild -list`, then build the `ParaSwift` package scheme for an iOS Simulator:

```bash
xcodebuild -scheme ParaSwift -destination 'generic/platform=iOS Simulator' -configuration Release build
```

A parent `ParaSwift.xcworkspace` is not part of this checkout and is not required.

### Format and Lint

```bash
swiftformat --swiftversion 6.1 .
```
> Run `swiftformat` before committing.

## Tests

Unit tests live in `Tests/ParaSwiftTests/` and are declared by the `ParaSwiftTests` target in `Package.swift`. Use Xcode's package test scheme with an installed iOS Simulator; this package targets iOS rather than macOS.

E2E/XCTest UI tests live in the canonical sibling `web-sdk/examples-hub/mobile/with-swift/exampleUITests/`. The standalone `examples-hub` repo is a mirror; make example changes in `web-sdk`.

From `web-sdk/examples-hub/mobile/with-swift`, run:

```bash
xcodebuild -project example.xcodeproj -scheme Example -testPlan Example \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' test
```

Choose an installed simulator using `xcrun simctl list devices available`. To select one test, add `-only-testing:exampleUITests/<TestClass>/<testMethodName>`. Test classes include `AuthenticationUITests`, `EVMWalletUITests`, `SolanaWalletUITests`, and `CosmosWalletUITests`.

The example project references the SDK as a package dependency. Check that dependency points to the SDK revision you intend to test; see `.github/workflows/run-ui-tests.yml` for the CI setup.

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
