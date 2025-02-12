# Para Swift SDK

  

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.7+-Orange?style=flat-square)
[![iOS](https://img.shields.io/badge/iOS-16.4+-yellowgreen?style=flat-square)](https://img.shields.io/badge/iOS-16.4+-Green?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

  
## Prerequisites

### Find your TeamID and Bundle Identifier
Your team id can be found from [Apple's developer portal](https://developer.apple.com/account/resources/certificates/list) in the top right corner of the Certificates, Identifiers & Profiles section.

<img width="1262" alt="Team ID" src="https://github.com/capsule-org/swift-sdk/assets/4346395/8804c237-5805-49e8-b7ef-845833646261">

Your bundle identifier can be found here

<img width="1547" alt="Bundle Identifier" src="https://github.com/capsule-org/swift-sdk/assets/4346395/84827d38-8477-422a-8e66-6c3ac6819095">

### Set up a Para Developer Portal Account and Configure Native Passkeys
To get an API Key and configure your team and bundle ids, please go to the [Developer Portal](https://developer.getpara.com/).

Once you've created an API key, please fill out the "Native Passkey Configuration" Section with your App Info described above. Please note that once entered, this information can take up to a day to be reflected by Apple. Ping us if you have any questions or if you would like to check in on the status of this

![image](https://github.com/user-attachments/assets/b04ae526-7aea-4dc0-a854-54499e17e6f5)

## Installation

  

### Swift Package Manager

  

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler.

  

Once you have your Swift package set up, adding ParaSwift as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift` or the Package list in Xcode.

  

```swift

dependencies: [

.package(url: "https://github.com/getpara/swift-sdk.git", .upToNextMajor(from: "1.0.0"))

]

```

  

Normally you'll want to depend on the `ParaSwift` target:

  

```swift

.product(name: "ParaSwift", package: "ParaSwift")

```

  

## Configuring You Project

  

ParaSwift utilizes native passkeys for authentication and wallet information. In order to use native passkeys in your app you will need several things

  

### Associated Domains



Under **Targets**->**AppName**->**Signing & Capabilities**, click on the **+Capability** button.

<img width="1483" alt="Capability" src="https://github.com/capsule-org/swift-sdk/assets/4346395/296ade64-552a-4833-9d24-4059335e82d2">

From the prompt that appears, search for and select **Associated Domains**

<img width="702" alt="Associated Domains" src="https://github.com/capsule-org/swift-sdk/assets/4346395/6570acd4-75a6-43d2-92cc-2da713a51246">


> **Note:** In order to add the associated domains capability to your project, you cannot use a personal team for the purposes of signing. If you are, you need to set up a company team with Apple.

In the associated domains section that appears after adding it, you will need to add two domains

1. webcredentials:app.beta.usecapsule.com
2. webcredentials:app.usecapsule.com

<img width="874" alt="Add Associated Domains" src="https://github.com/capsule-org/swift-sdk/assets/4346395/84c010e3-1377-4be4-ba74-6644781d78a4">
<img width="370" alt="AD Filled Out" src="https://github.com/capsule-org/swift-sdk/assets/4346395/3fb7a653-b90d-47b3-ae05-dd75905d3458">


This will allow you to use passkeys that have been created on any app that uses the Capsule system, so if your users already have a Capsule wallet they will be able to use it in your app.  


### Env File

In order to set your API Key and desired environment in the example app, please copy the file locations at Configs/example into the root level of your project and name it EnvDebug for development, and EnvRelease for production. This is only an example of how to manage your environment variables.

## Using ParaSwift

  

### Introduction

  

ParaSwift provides an interface to Capsule services from within iOS applications using SwiftUI (Support for UIKit coming soon).

  

### Configuring

  

To configure the capsule instance, you will need to create an instance of the capsule object as well as the globally available authorizationController environment object. This will be needed in several functions later on. If you need an API Key, please reach out to the Capsule Team.

  

### Creating a User

  

To create a user, you should first check in the provided email address exists, and if it does not then create it

  

```swift

Button("Sign Up") {

Task.init {

let userExists = try! await paraManager.checkIfUserExists(email: email)

if userExists {

return

}

try! await paraManager.createUser(email: email)

...

}

}

```

  

Upon success, the user should receive an email with a 6 digit verification pin. Call the verify function with the verification code acquired from this step. This will return a biometricsId which will be necessary to pass to the next function, generatePasskey.

  

Generate passkey takes in the authorizationController that was set up earlier. This is necessary to be able to allow the application to present the Passkey modals for creating and selecting a Passkey.

  

After generating the passkey, the last step is to create a wallet.

  

```swift

Button("Verify") {

Task.init {

let biometricsId = try! await paraManager.verify(verificationCode: code)

try! await paraManager.generatePasskey(email: email, biometricsId: biometricsId, authorizationController: authorizationController)

try! await paraManager.createWallet(skipDistributable: false)

}

}

```

  

After the wallet has been created, it will be set in the ParaManager object as a Published var.

  

### Signing a Message

  

To sign a message, all you need to do is pass in the id of the wallet you would like to use which can be obtained from the paraManager.wallet property, and the text that you would like to sign. This will produce a messageSignature.

  

```swift

Button("Sign Message") {

Task.init {

let messageSignature = try! await paraManager.signMessage(walletId: wallet.id, message: "Some message to sign")

...

}

}

```

## EVM Signer

You may also use the evm signer to sign messages, sign transactions, and send transactions

### Instantiating the signer

To start, you must instantiate the signer with your preferred JsonRPCProvider URL. For this example, we are using Infura Sepolia and the first wallet in the paraManager. The wallet is optional, and can be selected / changed after instantiation.

```swift
let paraEvmSigner = try! ParaEvmSigner(paraManager: paraManager, rpcUrl: "https://sepolia.infura.io/v3/<YOUR_API_KEY>", walletId: paraManager.wallets.first!.id)
```

### Select a Wallet

```swift
try! await paraEvmSigner.selectWallet(walletId: paraManager.wallets.first!.id)
```

### Signing a Message

```swift
let message = "Hello, World!"
let signature = try! await paraEvmSigner.signMessage(message)
print(signature)
```

### Signing a Transaction

To sign a transaction, you must first JSONEncode the transaction object, and then b64Encode the resulting data to get the base64 encoded string. This is what needs to be passed to the paraEvmSigner signTransaction function.

```swift
let transaction = Transaction(<TX_PARAMS>)
let encodedTransaction = try! JSONEncoder().encode(transaction)
let b64EncodedTransaction = encodedTransaction.base64EncodedString()
let signature = try! await paraEvmSigner.signTransaction(b64EncodedTransaction)
print(signature)
```

### Sending a Transaction

To send a transaction, you must first JSONEncode the transaction object, and then b64Encode the resulting data to get the base64 encoded string. This is what needs to be passed to the paraEvmSigner sendTransaction function.

```swift
let transaction = Transaction(<TX_PARAMS>)
let encodedTransaction = try! JSONEncoder().encode(transaction)
let b64EncodedTransaction = encodedTransaction.base64EncodedString()
let signedTx = try! await paraEvmSigner.sendTransaction(b64EncodedTransaction)
print(signedTx)
```

## MetaMask Integration

ParaSwift provides seamless integration with MetaMask Mobile through the `MetaMaskConnector` class. This allows your iOS app to connect with MetaMask wallets, sign messages, and send transactions.

### Setup MetaMask Connector

First, configure your app's Info.plist to allow querying MetaMask URL schemes:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>metamask</string>
</array>
```

This configuration is required to detect if MetaMask is installed on the device.

Then initialize the MetaMask connector with your app's configuration:

```swift
// Create MetaMask configuration
let bundleId = Bundle.main.bundleIdentifier ?? ""
let urlScheme = "your-app-scheme" // Must match URL scheme in Info.plist
let metaMaskConfig = MetaMaskConfig(
    appName: "Your App Name",
    appId: bundleId,
    apiVersion: "1.0"
)

// Initialize the connector
let metaMaskConnector = MetaMaskConnector(
    para: paraManager,
    appUrl: "https://\(bundleId)",  // Your app's URL
    deepLink: urlScheme,            // Your app's custom URL scheme
    config: metaMaskConfig
)
```

> **Note:** Make sure to configure your app's URL scheme in Info.plist under `CFBundleURLTypes`. The `deepLink` parameter should match this URL scheme.

### Handle Deep Links

Add deep link handling in your SwiftUI app's main entry point:

```swift
@main
struct YourApp: App {
    @StateObject private var metaMaskConnector: MetaMaskConnector
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handle MetaMask deep links
                    metaMaskConnector.handleURL(url)
                }
        }
    }
}
```

### Connect to MetaMask

Connect to MetaMask and get the user's accounts:

```swift
do {
    try await metaMaskConnector.connect()
    // Connection successful
    // Access connected accounts via metaMaskConnector.accounts
} catch {
    // Handle connection error
}
```

### Sign Messages

Request message signing from the connected MetaMask wallet:

```swift
guard let account = metaMaskConnector.accounts.first else { return }

do {
    let signature = try await metaMaskConnector.signMessage(
        "Message to sign",
        account: account
    )
    // Use the signature
} catch {
    // Handle signing error
}
```

### Send Transactions

Send transactions through the connected MetaMask wallet:

```swift
guard let account = metaMaskConnector.accounts.first else { return }

let transaction: [String: String] = [
    "from": account,
    "to": "0x...", // Recipient address
    "value": "0x...", // Value in wei (hex)
    "gasLimit": "0x..." // Gas limit (hex)
]

do {
    let txHash = try await metaMaskConnector.sendTransaction(
        transaction,
        account: account
    )
    // Transaction sent successfully
} catch {
    // Handle transaction error
}
```

### Properties

The MetaMask connector provides several useful properties:

- `isConnected`: Boolean indicating if MetaMask is connected
- `accounts`: Array of connected MetaMask account addresses
- `chainId`: Current chain ID (e.g., "0x1" for Ethereum mainnet)
