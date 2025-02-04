import SwiftUI
import ParaSwift
import web3swift
import Web3Core

struct Transaction: Codable {
    let to: String
    let value: String
    let gasLimit: String
    let maxPriorityFeePerGas: String
    let maxFeePerGas: String
    let nonce: String
    let chainId: String
}

/*
 {
     "to": "0x42c9a72c9dfcc92cae0de9510160cea2da27af91",
     "value": "1000000000000",
     "gasLimit": "21000",
     "maxPriorityFeePerGas": "1",
     "maxFeePerGas": "3",
     "nonce": "0",
     "chainId": "11155111",
     "smartContractAbi": "[{\"inputs\":[],\"name\":\"retrieve\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint256\",\"name\":\"num\",\"type\":\"uint256\"}],\"name\":\"store\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]",
     "smartContractFunctionName": "",
     "smartContractFunctionArgs": [],
     "smartContractByteCode": "",
     "type": 2
 }
 */

struct WalletView: View {
    @EnvironmentObject var paraManager: ParaManager
    @EnvironmentObject var appRootManager: AppRootManager
    
    @State private var messageToSign = ""
    @State private var result = ""
    @State private var creatingWallet = false
    @State private var isSigning = false
    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var balance: Int?
    
    
    private let web3 = Web3(provider: Web3HttpProvider(url: URL(string: "https://sepolia.infura.io/v3/961364684c7346c080994baab1469ea8")!, network: .Custom(networkID: 11155111)))
    
    private func fetchBalance() {
        let ethAddress = EthereumAddress(paraManager.wallets.first!.address!)!
        Task {
            let balance = try! await web3.eth.getBalance(for: ethAddress)
            self.balance = Int(balance)
        }
    }
    
    private func signTransaction() {
        var transaction: CodableTransaction = .emptyTransaction
        transaction.value = 100000000000000000
        transaction.gasLimit = 21000
        transaction.maxPriorityFeePerGas = 1
        transaction.nonce = 0
        transaction.maxFeePerGas = 3
        transaction.chainID = 11155111
        transaction.to = EthereumAddress("0x301d75d850c878b160ad9e1e3f6300202de9e97f")!
        let encodedTransaction = try! JSONEncoder().encode(transaction)
        let b64EncodedTransaction = encodedTransaction.base64EncodedString()

        Task {
            let _ = try! await paraManager.initEthersSigner(rpcUrl: "https://sepolia.infura.io/v3/961364684c7346c080994baab1469ea8", walletId: paraManager.wallets.first!.id)
            let sigHex = try! await paraManager.ethersSignTransaction(transactionB64: b64EncodedTransaction, walletId: paraManager.wallets.first!.id)
            print(sigHex)
        }
    }
    
    private func sendTransaction() {
        var transaction: CodableTransaction = .emptyTransaction
        transaction.value = 1000000000000000
        transaction.gasLimit = 21000
        transaction.maxPriorityFeePerGas = 1
        transaction.nonce = 0
        transaction.maxFeePerGas = 3
        transaction.chainID = 11155111
        transaction.to = EthereumAddress("0x301d75d850c878b160ad9e1e3f6300202de9e97f")!
        let encodedTransaction = try! JSONEncoder().encode(transaction)
        let b64EncodedTransaction = encodedTransaction.base64EncodedString()
        
        Task {
            let _ = try! await paraManager.initEthersSigner(rpcUrl: "https://sepolia.infura.io/v3/961364684c7346c080994baab1469ea8", walletId: paraManager.wallets.first!.id)
            let sigHex = try! await paraManager.ethersSendTransaction(transactionB64: b64EncodedTransaction, walletId: paraManager.wallets.first!.id)
            print(sigHex)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to your Wallet Home")
                .font(.title2)
                .bold()
            
            if let firstWallet = paraManager.wallets.first {
                // Unwrap address safely
                let address = firstWallet.address ?? "No Address Available"
                
                Text("Wallet Address: \(address)")
                    .font(.body)
                    .padding(.horizontal)
            
                if let balance {
                    Text("Balance: \(balance)")
                }
                
                TextField("Enter a message to sign", text: $messageToSign)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if isSigning {
                    ProgressView("Signing message...")
                }
                
                Button("Sign Message") {
                    guard !messageToSign.isEmpty else {
                        errorMessage = "Please enter a message to sign."
                        return
                    }
                    isSigning = true
                    errorMessage = nil
                    Task {
                        do {
                            let messageBytes = messageToSign.data(using: .utf8)
                            guard let base64Message = messageBytes?.base64EncodedString() else {
                                throw ParaError.bridgeError("Failed to encode message.")
                            }
                            let messageSignature = try await paraManager.signMessage(walletId: firstWallet.id, message: base64Message)
                            result = "Message Signature: \(messageSignature)"
                            isSigning = false
                        } catch {
                            isSigning = false
                            errorMessage = "Failed to sign message: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSigning || messageToSign.isEmpty)
                .padding(.horizontal)
                
                if isFetching {
                    ProgressView("Fetching wallets...")
                }
                
                // Buttons for session/wallet actions
                HStack {
                    Button("Check Session Active") {
                        isFetching = true
                        errorMessage = nil
                        Task {
                            do {
                                let active = try await paraManager.isSessionActive()
                                result = "Session Active: \(active)"
                                isFetching = false
                            } catch {
                                isFetching = false
                                errorMessage = "Failed to check session: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Fetch Wallets") {
                        isFetching = true
                        errorMessage = nil
                        Task {
                            do {
                                let wallets = try await paraManager.fetchWallets()
                                let addresses = wallets.map { $0.address ?? "No Address" }
                                result = "Wallet addresses: \(addresses.joined(separator: ", "))"
                                isFetching = false
                            } catch {
                                isFetching = false
                                errorMessage = "Failed to fetch wallets: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Copy Address") {
                        UIPasteboard.general.string = paraManager.wallets.first!.address!
                    }
                    .buttonStyle(.bordered)
                }
                
                HStack {
                    Button("Fetch Balance") {
                        fetchBalance()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Ethers Send Tx") {
                        sendTransaction()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Ethers Sign Tx") {
                        signTransaction()
                    }
                    .buttonStyle(.bordered)
                }
                
                Text(result)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                
                Spacer()
                
                Button("Logout") {
                    Task {
                        errorMessage = nil
                        do {
                            try await paraManager.logout()
                            appRootManager.currentRoot = .authentication
                        } catch {
                            errorMessage = "Failed to logout: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)
            } else {
                // No wallets found
                Text("No wallets found. Create one to get started.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if creatingWallet {
                    ProgressView("Creating Wallet...")
                }
                
                Button("Create Wallet") {
                    creatingWallet = true
                    errorMessage = nil
                    Task {
                        do {
                            try await paraManager.createWallet(skipDistributable: false)
                            creatingWallet = false
                        } catch {
                            creatingWallet = false
                            errorMessage = "Failed to create wallet: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(creatingWallet)
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Home")
    }
}
