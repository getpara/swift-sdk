import Foundation

/// Protocol for classes that support error tracking
@MainActor
protocol ErrorTrackable {
    /// The error reporting client instance
    var errorReportingClient: ErrorReportingClient? { get }

    /// Whether error tracking is enabled
    var isErrorTrackingEnabled: Bool { get }

    /// Get the current user ID for error context
    func getCurrentUserId() -> String?
}

extension ErrorTrackable {
    /// Track an error asynchronously without blocking the caller
    /// - Parameters:
    ///   - methodName: Name of the method where the error occurred
    ///   - error: The error that occurred
    ///   - userId: Optional user ID for context (defaults to getCurrentUserId())
    func trackError(methodName: String, error: Error, userId: String? = nil) async {
        guard isErrorTrackingEnabled, let client = errorReportingClient else {
            return
        }

        // Track the error asynchronously without blocking
        Task {
            await client.trackError(methodName: methodName, error: error, userId: userId ?? getCurrentUserId())
        }
    }

    /// Wrap async methods with error tracking
    /// This provides a functional approach to method wrapping without runtime method swizzling
    func withErrorTracking<T>(
        methodName: String,
        userId: String? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            await trackError(methodName: methodName, error: error, userId: userId)
            throw error
        }
    }

    /// Wrap synchronous methods with error tracking
    func withErrorTracking<T>(
        methodName: String,
        userId: String? = nil,
        operation: () throws -> T
    ) throws -> T {
        do {
            return try operation()
        } catch {
            Task {
                await trackError(methodName: methodName, error: error, userId: userId)
            }
            throw error
        }
    }
}
