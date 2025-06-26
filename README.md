# Para Swift SDK

[![Swift](https://img.shields.io/badge/Swift-5.10+-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.10+-Orange?style=flat-square)
[![iOS](https://img.shields.io/badge/iOS-16.0+-yellowgreen?style=flat-square)](https://img.shields.io/badge/iOS-16.0+-Green?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

The Para Swift SDK provides a native interface to Para services, enabling seamless integration of passkey-based wallets, transaction signing, and external wallet connections within your iOS applications.

## Prerequisites

### Find your TeamID and Bundle Identifier

Your team id can be found from [Apple's developer portal](https://developer.apple.com/account/resources/certificates/list) in the top right corner of the Certificates, Identifiers & Profiles section.

<img width="1262" alt="Team ID" src="https://github.com/capsule-org/swift-sdk/assets/4346395/8804c237-5805-49e8-b7ef-845833646261">

Your bundle identifier can be found in your Xcode project settings under **Targets** -> **Your App Name** -> **General** -> **Identity**.

<img width="1547" alt="Bundle Identifier" src="https://github.com/capsule-org/swift-sdk/assets/4346395/84827d38-8477-422a-8e66-6c3ac6819095">

### Set up a Para Developer Portal Account and Configure Native Passkeys

To get an API Key and configure your team and bundle ids, please go to the [Developer Portal](https://developer.getpara.com/).

Once you've created an API key, please fill out the "Native Passkey Configuration" Section with your App Info described above. Please note that once entered, this information can take up to a day to be reflected by Apple. Ping us if you have any questions or if you would like to check in on the status of this.

![image](https://github.com/user-attachments/assets/b04ae526-7aea-4dc0-a854-54499e17e6f5)

## Installation

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler.

Once you have your Swift package set up, adding ParaSwift as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift` or the Package list in Xcode.

```swift
// Package.swift dependencies
dependencies: [
    .package(url: "https://github.com/getpara/swift-sdk.git", .upToNextMajor(from: "1.2.1")) // Use the latest appropriate version
]

// Target dependencies
.target(
    name: "YourAppTarget",
    dependencies: [
        .product(name: "ParaSwift", package: "swift-sdk")
    ]
)
```

## Configuring Your Project

ParaSwift utilizes native passkeys (requiring iOS 16.4+) for authentication and wallet information. You need to configure your project to support this.

### Associated Domains (Required for Passkeys)

Under **Targets** -> **Your App Name** -> **Signing & Capabilities**, click on the **+ Capability** button.

<img width="1483" alt="Capability" src="https://github.com/capsule-org/swift-sdk/assets/4346395/296ade64-552a-4833-9d24-4059335e82d2">

Search for and select **Associated Domains**.

<img width="702" alt="Associated Domains" src="https://github.com/capsule-org/swift-sdk/assets/4346395/6570acd4-75a6-43d2-92cc-2da713a51246">

> **Note:** In order to add the associated domains capability to your project, you cannot use a personal team for the purposes of signing. If you are, you need to set up a company team with Apple.

In the associated domains section that appears, add the domains corresponding to the Para environments you intend to use:

1.  `webcredentials:app.usecapsule.com` (Production)
2.  `webcredentials:app.beta.usecapsule.com` (Beta)
3.  `webcredentials:app.sandbox.usecapsule.com` (Sandbox)
4.  If using a custom `.dev` environment, add `webcredentials:<your-relying-party-id>`

<img width="874" alt="Add Associated Domains" src="https://github.com/capsule-org/swift-sdk/assets/4346395/84c010e3-1377-4be4-ba74-6644781d78a4">
<img width="370" alt="AD Filled Out" src="https://github.com/capsule-org/swift-sdk/assets/4346395/3fb7a653-b90d-47b3-ae05-dd75905d3458">

This allows your app to use passkeys created by other apps within the Para ecosystem.

### App URL Scheme (Required for OAuth & MetaMask)

Under **Targets** -> **Your App Name** -> **Info**, expand **URL Types**.

Click the **+** button to add a new **URL Type**. Enter a unique identifier (e.g., your app's bundle ID) in the **Identifier** field and the same value in the **URL Schemes** field.

This scheme is used by Para to redirect back to your app after OAuth flows or MetaMask interactions. The SDK defaults to using your app's bundle identifier, but you can provide a custom scheme during `ParaManager` initialization if needed.

### MetaMask Query Scheme (Required for MetaMask Connector)

If using the `MetaMaskConnector`, add `metamask` to the `LSApplicationQueriesSchemes` array in your `Info.plist` to allow your app to check if MetaMask is installed.

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>metamask</string>
</array>
```

## Using ParaSwift

### Introduction

ParaSwift provides interfaces to Para services from within iOS applications using SwiftUI. The core components are:

*   `ParaManager`: Handles authentication, session state, wallet management, and basic signing.
*   `ParaEvmSigner`: Provides higher-level EVM-specific signing and transaction sending capabilities.
*   `MetaMaskConnector`: Facilitates interaction with the MetaMask mobile app.

### Initialization

Initialize the required SDK components, typically in your `App` struct or an initialization routine. It's recommended to manage API keys and environment settings securely (e.g., via environment variables or a configuration file).

```swift
import SwiftUI
import ParaSwift
import os

@main
struct YourApp: App {
    private let logger = Logger(subsystem: "com.yourcompany.yourapp", category: "YourApp")

    // State objects to hold the SDK components
    @StateObject private var paraManager: ParaManager
    @StateObject private var paraEvmSigner: ParaEvmSigner
    @StateObject private var metaMaskConnector: MetaMaskConnector

    // State for managing app flow (optional, example pattern)
    @StateObject private var appRootManager = AppRootManager() // Your custom state manager

    init() {
        // --- Load Configuration (Recommended) ---
        // Implement a way to securely load your API key, environment, etc.
        // See the example app's ParaConfig.swift for a pattern using environment variables.
        let apiKey = "YOUR_PARA_API_KEY" // Replace with your actual key
        let environment: ParaEnvironment = .beta // Or .sandbox, .prod, .dev(...)
        let rpcUrl = "YOUR_RPC_URL" // e.g., Infura Sepolia URL
        let appName = "Your App Name"
        let bundleId = Bundle.main.bundleIdentifier ?? "com.yourcompany.yourapp"
        let appUrl = "https://\(bundleId)" // Used for MetaMask originator info

        // --- Initialize ParaManager ---
        let manager = ParaManager(environment: environment, apiKey: apiKey)
        _paraManager = StateObject(wrappedValue: manager)

        // --- Initialize ParaEvmSigner ---
        // The EVM signer needs the ParaManager instance and an RPC URL.
        // You can optionally provide an initial wallet ID to select.
        do {
            let signer = try ParaEvmSigner(paraManager: manager, rpcUrl: rpcUrl, walletId: nil)
            _paraEvmSigner = StateObject(wrappedValue: signer)
        } catch {
            logger.critical("Failed to initialize Para EVM signer: \(error.localizedDescription)")
            // Handle fatal error appropriately in your app
            fatalError("EVM Signer Init Failed: \(error)")
        }

        // --- Initialize MetaMaskConnector ---
        let mmConfig = MetaMaskConfig(appName: appName, appId: bundleId)
        let connector = MetaMaskConnector(para: manager, appUrl: appUrl, config: mmConfig)
        _metaMaskConnector = StateObject(wrappedValue: connector)

        logger.info("Para SDK components initialized for environment: \(environment.name)")
    }

    var body: some Scene {
        WindowGroup {
            // Your main view, providing the SDK components via environment objects
            ContentView()
                .environmentObject(paraManager)
                .environmentObject(paraEvmSigner)
                .environmentObject(metaMaskConnector)
                .environmentObject(appRootManager) // Pass your state manager too
                .onOpenURL { url in
                    // Handle app scheme callbacks (required for OAuth & MetaMask)
                    logger.debug("Received app scheme callback: \(url.absoluteString)")
                    // Pass the URL to the MetaMask connector first
                    let handledByMetaMask = metaMaskConnector.handleURL(url)
                    if !handledByMetaMask {
                        // Add handling for other app scheme callbacks if necessary
                        logger.debug("URL not handled by MetaMask.")
                    }
                }
                // Example: React to session state changes (optional)
                .onChange(of: paraManager.sessionState) { newState in
                     logger.debug("ParaManager session state changed: \(String(describing: newState))")
                     // Update your app's UI flow based on the session state
                     // e.g., appRootManager.currentRoot = (newState == .activeLoggedIn) ? .home : .authentication
                }
        }
    }
}

// Example Content View accessing SDK components
struct ContentView: View {
    @EnvironmentObject var paraManager: ParaManager
    @EnvironmentObject var appRootManager: AppRootManager // Access your state manager

    var body: some View {
        // Example: Switch UI based on session state
        Group {
             switch paraManager.sessionState {
             case .unknown:
                 ProgressView("Initializing...") // Or a launch screen
             case .inactive:
                 AuthenticationView() // Your login/signup view
             case .active, .activeLoggedIn:
                 HomeView() // Your main authenticated view
             }
        }
        // Make SDK components available to child views if needed
        // .environmentObject(paraManager) // Already passed from App struct
        // .environmentObject(paraEvmSigner)
        // .environmentObject(metaMaskConnector)
    }
}

// Placeholder views
struct AuthenticationView: View {
    var body: some View { Text("Login/Signup Screen") }
}
struct HomeView: View {
     var body: some View { Text("Authenticated Home Screen") }
}
// Your custom AppRootManager class
class AppRootManager: ObservableObject { /* ... */ }

```

### Authentication

The SDK provides high-level methods to handle common authentication flows using passkeys. You'll need to provide an `ASAuthorizationController` instance, which can be obtained from the SwiftUI environment.

**Required Environment Values:**

Make sure your views have access to these environment values when performing authentication:

```swift
@Environment(\.authorizationController) private var authorizationController
@Environment(\.webAuthenticationSession) private var webAuthenticationSession // Needed for OAuth
```

**1. Email Authentication:**

Handles signup or login using an email address and passkeys. It manages the verification step if required.

```swift
import SwiftUI
import ParaSwift

struct EmailLoginView: View {
    @EnvironmentObject var paraManager: ParaManager
    @EnvironmentObject var appRootManager: AppRootManager // Your state manager
    @Environment(\.authorizationController) private var authorizationController

    @State private var email = ""
    @State private var verificationCode = ""
    @State private var needsVerification = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    func authenticate() {
        isLoading = true
        errorMessage = nil
        Task {
            let result = await paraManager.handleEmailAuth(
                email: email,
                verificationCode: needsVerification ? verificationCode : nil,
                authorizationController: authorizationController
            )
            isLoading = false

            switch result.status {
            case .success:
                appRootManager.currentRoot = .home // Navigate to home
            case .needsVerification:
                needsVerification = true // Show verification code input
                errorMessage = "Please check your email for a verification code."
            case .error:
                errorMessage = result.errorMessage ?? "An unknown error occurred."
                needsVerification = false // Reset verification state on error
            }
        }
    }

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .disabled(isLoading || needsVerification)

            if needsVerification {
                TextField("Verification Code", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .disabled(isLoading)
                Button("Resend Code") {
                    Task { try? await paraManager.resendVerificationCode() }
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }

            Button(needsVerification ? "Verify Code" : "Continue with Email") {
                authenticate()
            }
            .disabled(isLoading || email.isEmpty || (needsVerification && verificationCode.isEmpty))
            .buttonStyle(.borderedProminent)

            if isLoading { ProgressView() }

            // Optional: Direct Passkey Login Button
            Button("Log In with Existing Passkey") {
                 isLoading = true
                 Task {
                     do {
                         // Use nil authInfo to prompt for any passkey associated with the relying party
                         try await paraManager.loginWithPasskey(authorizationController: authorizationController, authInfo: nil)
                         appRootManager.currentRoot = .home
                     } catch {
                         errorMessage = "Passkey login failed: \(error.localizedDescription)"
                     }
                     isLoading = false
                 }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
        .padding()
    }
}
```

**2. Phone Number Authentication:**

Similar to email, but uses a phone number. Requires formatting the number correctly.

```swift
import SwiftUI
import ParaSwift

struct PhoneLoginView: View {
    @EnvironmentObject var paraManager: ParaManager
    @EnvironmentObject var appRootManager: AppRootManager
    @Environment(\.authorizationController) private var authorizationController

    @State private var phoneNumber = "" // User enters national number
    @State private var countryCode = "1" // User selects country code (e.g., "1" for US/Canada)
    @State private var verificationCode = ""
    @State private var needsVerification = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    // You'll need UI to select the country code

    func authenticate() {
        isLoading = true
        errorMessage = nil
        Task {
            // Note: paraManager.handlePhoneAuth expects the *national* number and country code separately.
            let result = await paraManager.handlePhoneAuth(
                phoneNumber: phoneNumber, // e.g., "5551234567"
                countryCode: countryCode, // e.g., "1"
                verificationCode: needsVerification ? verificationCode : nil,
                authorizationController: authorizationController
            )
            isLoading = false

            switch result.status {
            case .success:
                appRootManager.currentRoot = .home
            case .needsVerification:
                needsVerification = true
                errorMessage = "Please check your phone for a verification code."
            case .error:
                errorMessage = result.errorMessage ?? "An unknown error occurred."
                needsVerification = false
            }
        }
    }

    var body: some View {
        VStack {
            // UI for country code selection (e.g., Picker or custom view)
            HStack {
                 Text("+\(countryCode)") // Display selected country code
                 TextField("Phone Number", text: $phoneNumber)
                     .keyboardType(.phonePad)
                     .disabled(isLoading || needsVerification)
            }

            if needsVerification {
                TextField("Verification Code", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .disabled(isLoading)
                Button("Resend Code") {
                    Task { try? await paraManager.resendVerificationCode() }
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }

            Button(needsVerification ? "Verify Code" : "Continue with Phone") {
                authenticate()
            }
            .disabled(isLoading || phoneNumber.isEmpty || (needsVerification && verificationCode.isEmpty))
            .buttonStyle(.borderedProminent)

            if isLoading { ProgressView() }

             // Optional: Direct Passkey Login Button (same as email example)
        }
        .padding()
    }
}
```

**3. OAuth Authentication (Google, Discord, Apple):**

Handles OAuth flows, linking them to a passkey account. Requires the `webAuthenticationSession` environment value.

```swift
import SwiftUI
import ParaSwift
import AuthenticationServices // For ASWebAuthenticationSession

struct OAuthLoginView: View {
    @EnvironmentObject var paraManager: ParaManager
    @EnvironmentObject var appRootManager: AppRootManager
    @Environment(\.authorizationController) private var authorizationController
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession // Required

    @State private var isLoading = false
    @State private var errorMessage: String?

    func authenticate(provider: OAuthProvider) {
        isLoading = true
        errorMessage = nil
        Task {
            let result = await paraManager.handleOAuth(
                provider: provider,
                webAuthenticationSession: webAuthenticationSession,
                authorizationController: authorizationController
            )
            isLoading = false

            if result.success {
                appRootManager.currentRoot = .home
            } else {
                errorMessage = result.errorMessage ?? "OAuth failed."
            }
        }
    }

    var body: some View {
        VStack(spacing: 15) {
            Button("Continue with Google") { authenticate(provider: .google) }
                .buttonStyle(.borderedProminent).disabled(isLoading)
            Button("Continue with Discord") { authenticate(provider: .discord) }
                .buttonStyle(.borderedProminent).disabled(isLoading)
            Button("Continue with Apple") { authenticate(provider: .apple) }
                .buttonStyle(.borderedProminent).disabled(isLoading)

            if let error = errorMessage {
                Text(error).foregroundColor(.red).padding(.top)
            }
            if isLoading { ProgressView().padding(.top) }
        }
        .padding()
    }
}
```

**4. External Wallet Login (MetaMask Example):**

Used primarily by connectors like `MetaMaskConnector` after a successful connection.

```swift
// This is typically called *internally* by the MetaMaskConnector after a successful connection.
// You usually don't call this directly unless implementing a custom external wallet flow.

// Inside MetaMaskConnector.swift's handleConnectResult method:
// ... after getting accounts ...
guard let address = accounts.first, !address.isEmpty else {
    // Handle error: No address received
    return
}
do {
    // Login to Para using the external EVM address
    try await para.loginExternalWallet(externalAddress: address, type: "EVM")
    // Update session state, complete continuation, etc.
} catch {
    // Handle external login error
}
```

### Session Management

Check the user's session status and log them out.

```swift
// Check if a user session is active (partially logged in)
let isActive = try await paraManager.isSessionActive()

// Check if the user is fully logged in (session active AND passkey verified)
let isLoggedIn = try await paraManager.isFullyLoggedIn()

// Access the current session state
let currentState = paraManager.sessionState // .unknown, .inactive, .active, .activeLoggedIn

// Logout
Button("Logout") {
    Task {
        do {
            try await paraManager.logout()
            // Update app state to show login screen
            appRootManager.currentRoot = .authentication
        } catch {
            // Handle logout error
            print("Logout failed: \(error)")
        }
    }
}
```

### Wallet Management

Create and fetch user wallets.

```swift
// Create a new EVM wallet (passkey must be set up first)
// This is often done automatically during signup flows (handleEmailAuth, etc.)
Button("Create EVM Wallet") {
    Task {
        do {
            // type: .evm, .solana, .cosmos
            // skipDistributable: Set to true if you don't need multi-device recovery initially
            try await paraManager.createWallet(type: .evm, skipDistributable: false)
            // Wallet creation automatically updates paraManager.wallets and sessionState
        } catch {
            print("Failed to create wallet: \(error)")
        }
    }
}

// Fetch existing wallets
Button("Refresh Wallets") {
    Task {
        do {
            // fetchWallets returns the list but also updates the published `paraManager.wallets`
            let fetchedWallets = try await paraManager.fetchWallets()
            print("Fetched \(fetchedWallets.count) wallets.")
        } catch {
            print("Failed to fetch wallets: \(error)")
        }
    }
}

// Accessing wallets (e.g., in a SwiftUI View)
struct WalletListView: View {
    @EnvironmentObject var paraManager: ParaManager

    var body: some View {
        List(paraManager.wallets, id: \.id) { wallet in
            VStack(alignment: .leading) {
                Text("ID: \(wallet.id)").font(.caption)
                Text("Type: \(wallet.type?.rawValue ?? "N/A")")
                Text("Address: \(wallet.address ?? "N/A")").lineLimit(1).truncationMode(.middle)
            }
        }
    }
}
```

### ParaManager Signing (Lower-Level)

`ParaManager` provides basic signing methods. These might require you to handle encoding/decoding. For EVM, prefer `ParaEvmSigner`.

```swift
// Sign an arbitrary message (requires Base64 encoding)
let message = "Your message here"
let base64Message = Data(message.utf8).base64EncodedString()
do {
    // Ensure you have fetched wallets and have a wallet ID
    guard let walletId = paraManager.wallets.first?.id else { return }
    let signature = try await paraManager.signMessage(
        walletId: walletId,
        message: base64Message // Pass the base64 encoded message
    )
    print("ParaManager Signature: \(signature)")
} catch {
    print("ParaManager signing failed: \(error)")
}

// Sign a pre-encoded transaction (requires RLP and Base64 encoding)
// This is complex; prefer ParaEvmSigner for EVM transactions.
let rlpEncodedTx = "YOUR_RLP_ENCODED_TX_HEX" // Hex string of RLP encoded tx
let base64RlpEncodedTx = Data(hex: rlpEncodedTx).base64EncodedString() // You need Data(hex:) extension
let chainId = "11155111" // e.g., Sepolia
do {
    guard let walletId = paraManager.wallets.first?.id else { return }
    let signature = try await paraManager.signTransaction(
        walletId: walletId,
        rlpEncodedTx: base64RlpEncodedTx, // Pass base64 of RLP encoded tx
        chainId: chainId
    )
    print("ParaManager Tx Signature: \(signature)")
} catch {
     print("ParaManager tx signing failed: \(error)")
}
```

### EVM Signer

Use `ParaEvmSigner` for streamlined EVM operations.

```swift
import SwiftUI
import ParaSwift
import BigInt // Required for EVMTransaction values

struct EvmOperationsView: View {
    @EnvironmentObject var paraEvmSigner: ParaEvmSigner
    @EnvironmentObject var paraManager: ParaManager // To get wallet ID

    @State private var selectedWalletId: String?
    @State private var messageToSign = "Hello Para EVM Signer!"
    @State private var signResult: String?
    @State private var sendResult: String?
    @State private var isLoading = false

    // Select the wallet to use with the signer
    func selectWallet() {
        guard let walletId = paraManager.wallets.first(where: { $0.type == .evm })?.id else {
            print("No EVM wallet found")
            return
        }
        isLoading = true
        Task {
            do {
                try await paraEvmSigner.selectWallet(walletId: walletId)
                self.selectedWalletId = walletId
                print("EVM Signer selected wallet: \(walletId)")
            } catch {
                print("Failed to select wallet for EVM Signer: \(error)")
            }
            isLoading = false
        }
    }

    // Sign a simple message
    func signEvmMessage() {
        guard selectedWalletId != nil else { print("No wallet selected"); return }
        isLoading = true
        Task {
            do {
                let signature = try await paraEvmSigner.signMessage(message: messageToSign)
                signResult = "Signature: \(signature)"
            } catch {
                signResult = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    // Sign and Send an EVM Transaction
    func sendEvmTransaction() {
        guard selectedWalletId != nil else { print("No wallet selected"); return }
        isLoading = true
        Task {
            do {
                // 1. Create the transaction object
                let transaction = EVMTransaction(
                    to: "0xRecipientAddress...", // Replace with actual address
                    value: BigUInt("10000000000000000"), // 0.01 ETH in Wei
                    gasLimit: BigUInt(21000),
                    // Add other params like chainId, nonce, gasPrice/fees if needed
                    chainId: BigUInt(11155111) // Sepolia
                    // type: 2 // For EIP-1559
                )

                // 2. Get the Base64 encoded transaction
                let b64EncodedTx = transaction.b64Encoded()

                // 3. Send the transaction
                let txResult = try await paraEvmSigner.sendTransaction(transactionB64: b64EncodedTx)
                // The result format might vary; inspect it (could be tx hash, receipt, etc.)
                sendResult = "Send Result: \(String(describing: txResult))"

            } catch {
                sendResult = "Send Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            if selectedWalletId == nil {
                Button("Select EVM Wallet First", action: selectWallet)
            } else {
                Text("Using Wallet: \(selectedWalletId ?? "")")
                TextField("Message", text: $messageToSign)
                Button("Sign Message (EVM)", action: signEvmMessage)
                if let res = signResult { Text(res).font(.caption) }

                Button("Send 0.01 ETH (Sepolia)", action: sendEvmTransaction)
                if let res = sendResult { Text(res).font(.caption) }
            }
            if isLoading { ProgressView() }
        }
        .padding()
        .onAppear(perform: selectWallet) // Select wallet when view appears
    }
}
```

### MetaMask Integration

Use `MetaMaskConnector` to interact with the MetaMask mobile app.

**Setup:**

1.  Add `metamask` to `LSApplicationQueriesSchemes` in `Info.plist`.
2.  Configure your app's URL scheme in `Info.plist` under `URL Types`.
3.  Handle incoming URLs in your `App` struct's `.onOpenURL` modifier and pass them to `metaMaskConnector.handleURL(url)`.

**Usage:**

```swift
import SwiftUI
import ParaSwift
import BigInt // For EVMTransaction

struct MetaMaskView: View {
    @EnvironmentObject var metaMaskConnector: MetaMaskConnector
    @EnvironmentObject var appRootManager: AppRootManager // To navigate on connect

    @State private var isLoading = false
    @State private var operationResult: String?

    var body: some View {
        VStack(spacing: 20) {
            if metaMaskConnector.isConnected {
                Text("Connected Account: \(metaMaskConnector.accounts.first ?? "N/A")")
                Text("Chain ID: \(metaMaskConnector.chainId ?? "N/A")")

                Button("Sign Message (MetaMask)") { signWithMetaMask() }
                    .disabled(isLoading)

                Button("Send 0.001 ETH (MetaMask)") { sendWithMetaMask() }
                    .disabled(isLoading)

            } else {
                Button("Connect to MetaMask") { connectMetaMask() }
                    .disabled(isLoading)
            }

            if let result = operationResult {
                Text(result).font(.caption).padding(.top)
            }
            if isLoading { ProgressView().padding(.top) }
        }
        .padding()
    }

    func connectMetaMask() {
        isLoading = true
        Task {
            do {
                try await metaMaskConnector.connect()
                // Connection successful, MetaMaskConnector automatically calls
                // paraManager.loginExternalWallet and updates its own state.
                // You might want to navigate or update UI here.
                // Example: appRootManager.currentRoot = .home
                operationResult = "Connected!"
            } catch {
                operationResult = "Connection failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func signWithMetaMask() {
        guard metaMaskConnector.isConnected, let account = metaMaskConnector.accounts.first else { return }
        isLoading = true
        Task {
            do {
                let message = "Sign this message via MetaMask!"
                let signature = try await metaMaskConnector.signMessage(message, account: account)
                operationResult = "MetaMask Signature: \(signature)"
            } catch {
                 operationResult = "MetaMask Sign Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func sendWithMetaMask() {
         guard metaMaskConnector.isConnected, let account = metaMaskConnector.accounts.first else { return }
         isLoading = true
         Task {
             do {
                 // Create EVMTransaction
                 let transaction = EVMTransaction(
                     to: "0xRecipientAddress...", // Replace
                     value: BigUInt("1000000000000000"), // 0.001 ETH in Wei
                     gasLimit: BigUInt(21000)
                     // MetaMask will prompt for chain details if needed
                 )
                 let txHash = try await metaMaskConnector.sendTransaction(transaction, account: account)
                 operationResult = "MetaMask Tx Sent: \(txHash)"
             } catch {
                 operationResult = "MetaMask Send Error: \(error.localizedDescription)"
             }
             isLoading = false
         }
    }
}
```
```
