import SwiftUI
import os

// MARK: - Wallet Management
extension ParaManager {
    /// Creates a new wallet of the specified type, refreshes the wallet list, and returns any recovery secret.
    ///
    /// Note: This function initiates wallet creation and immediately fetches the updated wallet list.
    /// The UI should observe the `wallets` property for updates.
    ///
    /// - Parameters:
    ///   - type: The type of wallet to create.
    ///   - skipDistributable: Whether to skip distributable shares.
    @MainActor
    public func createWallet(type: WalletType, skipDistributable: Bool) async throws {
        try await ensureWebViewReady()
        // Call createWallet but ignore the result as we fetch wallets separately
        _ = try await postMessage(method: "createWallet", payload: CreateWalletArgs(type: type.rawValue, skipDistributable: skipDistributable))

        logger.debug("Wallet creation initiated for type \(type.rawValue). Refreshing wallet list...")

        // Fetch the complete list of wallets to update the list immediately
        let allWallets = try await fetchWallets()

        // Update the local wallets list with the complete fetched data
        self.wallets = allWallets
        self.sessionState = .activeLoggedIn // Update state as wallet creation implies login

        logger.debug("Wallet list refreshed after creation. Found \(allWallets.count) wallets.")

        // No return value
    }

    /// Fetches all wallets associated with the current user.
    ///
    /// - Returns: Array of wallet objects.
    public func fetchWallets() async throws -> [Wallet] {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "fetchWallets", payload: EmptyPayload())
        let walletsData = try decodeResult(result, expectedType: [[String: Any]].self, method: "fetchWallets")
        return walletsData.map { Wallet(result: $0) }
    }

    /// Distributes a new wallet share to another user.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to share.
    ///   - userShare: The user share.
    public func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "distributeNewWalletShare", payload: DistributeNewWalletShareArgs(walletId: walletId, userShare: userShare))
    }

    /// Gets the current user's email address.
    ///
    /// - Returns: Email address as a string.
    public func getEmail() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "getEmail", payload: EmptyPayload())
        return try decodeResult(result, expectedType: String.self, method: "getEmail")
    }
}
