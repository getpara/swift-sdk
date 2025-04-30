import SwiftUI // Keep if @MainActor is used
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

    /// Helper method to refresh wallets with retry logic
    internal func refreshWalletsWithRetry(maxAttempts: Int = 5, isSignup: Bool = false) async {
        let logger: Logger = Logger(subsystem: "com.paraSwift", category: "WalletRefresh")

        // For signup, wallets can take longer to be available
        let delayBetweenAttempts: UInt64 = isSignup ? 3_000_000_000 : 1_500_000_000 // 3 seconds for signup, 1.5 for login

        for attempt in 1...maxAttempts {
            do {
                logger.debug("Attempting to fetch wallets (attempt \(attempt)/\(maxAttempts))...")
                let newWallets: [Wallet] = try await fetchWallets()

                if !newWallets.isEmpty {
                    logger.debug("Successfully fetched \(newWallets.count) wallets")
                    self.wallets = newWallets

                    // Ensure session state is updated
                    self.sessionState = .activeLoggedIn
                    return
                } else {
                    logger.debug("Fetched empty wallet list, retrying in \(delayBetweenAttempts/1_000_000_000) seconds...")

                    // Check if we're logged in even though wallets aren't available yet
                    if let isLoggedIn: Bool = try? await isFullyLoggedIn(), isLoggedIn {
                        logger.debug("User is fully logged in despite no wallets yet - continuing to wait")
                    }

                    try await Task.sleep(nanoseconds: delayBetweenAttempts)
                }
            } catch {
                logger.error("Error fetching wallets: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: delayBetweenAttempts)
            }
        }

        logger.warning("Failed to fetch wallets after \(maxAttempts) attempts")
    }
}
