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
            logger.info("Error reported successfully for method: \(methodName)")
        } catch {
            // Silent failure to prevent error reporting loops
            logger.error("Failed to report error for method \(methodName): \(error)")
        }
    }
    
    /// Send error payload to the API
    private func sendErrorToAPI(payload: ErrorPayload) async throws {
        let urlString = "\(baseURL)/errors/sdk"
        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL: \(urlString)")
            throw ErrorReportingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Response is not HTTPURLResponse")
                throw ErrorReportingError.networkError
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
                logger.error("HTTP \(httpResponse.statusCode) error. Response: \(responseBody)")
                throw ErrorReportingError.networkError
            }
        } catch {
            logger.error("Failed to send error report: \(error.localizedDescription)")
            throw error
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