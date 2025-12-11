# Release 2.6.0 (Thu Dec 11 2025)

### Features
- Added `issueJwt()` method for server-side authentication - issue JWTs that can be verified server-side using Para's JWKS endpoint at `/.well-known/jwks.json` (#37)
- Added `JwtResponse` struct containing the signed token and key ID for JWKS lookup (#37)

# Release 2.5.0 (Tue Nov 05 2025)

### Features
- Added account deletion capability, allowing users to permanently delete their Para account and associated data (#36)
- Simplified quick login flow by introducing optional default web authentication session, reducing boilerplate code for repeated OAuth operations

### Changes
- Migrated quick login logic from bridge to SDK for improved maintainability and direct control over authentication flows
- Added `setDefaultWebAuthenticationSession()` method to set a default session for hosted auth flows
- Made `webAuthenticationSession` parameter optional in `handleOAuth()` when a default session is configured

# Release 2.4.0 (Mon Oct 20 2025)

### Features
- Added automatic session persistence across app launches, allowing users to remain authenticated after closing and reopening the app (#35)

# Release 2.3.0 (Tue Oct 14 2025)

### Features
- Added Single Logout (SLO) support with dedicated bridge layer architecture (#34)

### Fixes
- Fixed login URL encoding to properly handle special characters and query parameters

# Release 2.2.0 (Tue Jan 03 2025)

### Features
- Added support for returning complete RLP-encoded signed transactions for EVM chains, enabling direct submission to blockchain networks (#33)
- Extended `SignatureResult` struct with `signedTransaction` field for full EVM transaction data (#33)

### Fixes
- Fixed duplicate loading of transmission keyshares which could cause performance issues

### Changes
- Enhanced EVM transaction signing to provide both signature and complete signed transaction while maintaining backward compatibility (#33)

# Release 2.1.0 (Tue Aug 27 2025)

### Breaking Changes
- Removed chain-specific signer classes - `ParaEvmSigner`, `ParaSolanaWeb3Signer`, `ParaCosmosSigner` have been removed in favor of unified methods on `ParaManager` (#32)
- Updated signing method signatures - `signMessage()` now returns `SignatureResult` instead of `String`, `signTransaction()` now accepts transaction model objects instead of RLP-encoded strings (#32)

### Features
- Unified wallet architecture - All signing and formatting logic moved to bridge, reducing SDK complexity (#32)
- Type-safe transaction models - New `EVMTransaction`, `SolanaTransaction`, and `CosmosTransaction` classes with builders (#32)
- Enhanced signature results - Signing methods now return metadata including wallet ID and type (#32)
- Improved error messages - Clearer, actionable error descriptions without technical prefixes (#30)

### Improvements
- Reduced package size - Removed `solana-swift` dependency, all blockchain formatting handled by bridge (#32)

### Fixes
- Fixed password authentication wallet persistence issue (#31)

### Migration Guide
```swift
// Signer classes migration:
// Before: let evmSigner = ParaEvmSigner(...)
// After: Use para.signTransaction() directly

// Transaction signing:
// Before: para.signTransaction(walletId, rlpEncodedTx, chainId)
// After: para.signTransaction(walletId, EVMTransaction(...))
```

# Release 2.0.1 (Thu Aug 14 2025)

### Features
- Added comprehensive error tracking system for development and staging environments (#29)

### Fixes
- Fixed password login wallet persistence to resolve "wallet with id does not exist" errors after authentication (#31)

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
