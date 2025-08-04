import Foundation
import os

/// HTTP client for sending error reports to Para's error tracking service
@MainActor
internal class ErrorReportingClient {
    private let baseURL: String
    private let apiKey: String
    private let logger = Logger(subsystem: "ParaSwift", category: "ErrorReporting")
    
    /// Initialize the error reporting client
    /// - Parameters:
    ///   - baseURL: Base URL for the Para API
    ///   - apiKey: API key for authentication
    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
    
    /// Track an error by sending it to Para's error reporting service
    /// - Parameters:
    ///   - methodName: Name of the method where the error occurred
    ///   - error: The error that occurred
    ///   - userId: Optional user ID for context
    func trackError(methodName: String, error: Error, userId: String? = nil) async {
        do {
            let payload = ErrorPayload(
                methodName: methodName,
                error: ErrorInfo(
                    name: String(describing: type(of: error)),
                    message: error.localizedDescription
                ),
                sdkType: "SWIFT",
                userId: userId
            )
            
            try await sendErrorToAPI(payload: payload)
            logger.debug("Error reported successfully for method: \(methodName)")
        } catch {
            // Silent failure to prevent error reporting loops
            logger.error("Failed to report error for method \(methodName): \(error)")
        }
    }
    
    /// Send error payload to the API
    private func sendErrorToAPI(payload: ErrorPayload) async throws {
        guard let url = URL(string: "\(baseURL)/errors/sdk") else {
            throw ErrorReportingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ErrorReportingError.networkError
        }
    }
}

// MARK: - Error Payload Models

private struct ErrorPayload: Codable {
    let methodName: String
    let error: ErrorInfo
    let sdkType: String
    let userId: String?
}

private struct ErrorInfo: Codable {
    let name: String
    let message: String
}

// MARK: - Error Types

private enum ErrorReportingError: Error {
    case invalidURL
    case networkError
}