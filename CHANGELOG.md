# Release 2.0.0 (Thu Aug 07 2025)

## Package Version
- para-swift@2.0.0

### Breaking Changes
- **BREAKING CHANGE** Implement V2 Authentication Bridge with improved OAuth support and API simplification
- **BREAKING CHANGE** Rename `deeplinkUrl` to `appScheme` in OAuth parameters for clarity

### Features
- Add Cosmos blockchain support to Swift SDK
- Add Solana blockchain integration support 
- Add password authentication support
- Add AuthInfo getter for mobile SDKs
- Pass `isPasskeySupported` boolean to bridge initializer
- Support for alpha bridge on beta/prod environments
- OAuth improvements with better error handling

### Fixes
- Fix external wallet authentication for alpha environment
- Simplify MetaMask authentication flow
- Phone number formatting improvements

### Chores
- Add changelog generation script for Swift SDK releases
- Add Claude Code GitHub workflow for automated assistance
- Add E2E tests with GitHub Actions CI
- Update ParaBump configuration
- Add PR reminders workflow
- Don't create EVM wallet automatically
- Add production-ready logging for API key debugging
- Run swiftformat on codebase

### Documentation
- Update README and workflow documentation


# Release 1.2.1 (Wed Aug 06 2025)

## Package Version
- para-swift@1.2.1

### Features
- always enable error reporting in Swift SDK
- add error reporting client for Swift SDK
- add automatic wallet creation after signup (#26)
- add persistent session management to SwiftUI ParaManager

### Fixes
- implement getCurrentUserId() to return actual user ID from wallets
- correct production API URL for error reporting

### Chores
- Rename deepLink to appScheme for clarity
