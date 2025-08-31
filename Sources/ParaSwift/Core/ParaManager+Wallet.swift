import os
import SwiftUI

// MARK: - Wallet Management

public extension ParaManager {
    /// Creates a new wallet of the specified type, refreshes the wallet list, and returns any recovery secret.
    ///
    /// Note: This function initiates wallet creation and immediately fetches the updated wallet list.
    /// The UI should observe the `wallets` property for updates.
    ///
    /// - Parameters:
    ///   - type: The type of wallet to create.
    ///   - skipDistributable: Whether to skip distributable shares.
    @MainActor
    func createWallet(type: WalletType, skipDistributable: Bool) async throws {
        try await ensureWebViewReady()
        // Call createWallet but ignore the result as we fetch wallets separately
        _ = try await postMessage(method: "createWallet", payload: CreateWalletArgs(type: type.rawValue, skipDistributable: skipDistributable))

        logger.debug("Wallet creation initiated for type \(type.rawValue). Refreshing wallet list...")

        // Fetch the complete list of wallets to update the list immediately
        let allWallets = try await fetchWallets()

        // Update the local wallets list with the complete fetched data
        wallets = allWallets
        sessionState = .activeLoggedIn // Update state as wallet creation implies login

        logger.debug("Wallet list refreshed after creation. Found \(allWallets.count) wallets.")

        // No return value
    }

    /// Fetches all wallets associated with the current user.
    ///
    /// - Returns: Array of wallet objects.
    /// - Note: This method automatically ensures transmission keyshares are loaded before fetching wallets.
    func fetchWallets() async throws -> [Wallet] {
        try await ensureWebViewReady()
        
        // Automatically load transmission keyshares if not already loaded
        // This ensures wallet signers are properly populated from the backend
        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            // Log the error but continue with fetching wallets
            // Some operations may still work without transmission keyshares
            logger.warning("Failed to load transmission keyshares before fetching wallets: \(error.localizedDescription)")
        }
        
        let result = try await postMessage(method: "fetchWallets", payload: EmptyPayload())
        let walletsData = try decodeResult(result, expectedType: [[String: Any]].self, method: "fetchWallets")
        return walletsData.map { Wallet(result: $0) }
    }

    /// Distributes a new wallet share to another user.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to share.
    ///   - userShare: The user share.
    func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "distributeNewWalletShare", payload: DistributeNewWalletShareArgs(walletId: walletId, userShare: userShare))
    }

    /// Gets the current user's email address.
    ///
    /// - Returns: Email address as a string.
    func getEmail() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "getEmail", payload: EmptyPayload())
        return try decodeResult(result, expectedType: String.self, method: "getEmail")
    }

    /// Synchronizes required wallets by creating any missing non-optional wallet types.
    /// This should be called after successful authentication for new users.
    ///
    /// - Returns: Array of newly created wallets, if any.
    @MainActor
    func synchronizeRequiredWallets() async throws -> [Wallet] {
        logger.info("Starting wallet synchronization...")
        
        // Call createWalletPerType without types parameter
        // This will automatically create wallets for all missing required types
        let result = try await postMessage(method: "createWalletPerType", payload: CreateWalletPerTypeArgs())
        
        guard let resultDict = result as? [String: Any],
              let walletsArray = resultDict["wallets"] as? [[String: Any]] else {
            logger.error("Invalid response from createWalletPerType")
            return []
        }
        
        let newWallets = walletsArray.map { Wallet(result: $0) }
        
        if !newWallets.isEmpty {
            logger.info("Created \(newWallets.count) required wallets")
            // Update local wallets list
            wallets = try await fetchWallets()
        } else {
            logger.info("No new wallets created - all required types already exist")
        }
        
        return newWallets
    }
}
