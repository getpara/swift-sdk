import Foundation
import os
import UIKit

/// HTTP client for sending error reports to Para's error tracking service
@MainActor
internal class ErrorReportingClient {
    private let baseURL: String
    private let apiKey: String
    private let environment: String
    private let logger = Logger(subsystem: "ParaSwift", category: "ErrorReporting")
    
    /// Initialize the error reporting client
    /// - Parameters:
    ///   - baseURL: Base URL for the Para API
    ///   - apiKey: API key for authentication
    ///   - environment: Environment name for context
    init(baseURL: String, apiKey: String, environment: String = "PROD") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.environment = environment
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
                    message: extractErrorMessage(from: error)
                ),
                sdkType: "SWIFT",
                sdkVersion: ParaPackage.version,
                environment: environment,
                deviceInfo: DeviceInfo(
                    model: deviceModel,
                    osVersion: osVersion
                ),
                userId: userId
            )
            
            try await sendErrorToAPI(payload: payload)
            logger.info("Error reported successfully for method: \(methodName)")
        } catch {
            // Silent failure to prevent error reporting loops
            logger.error("Failed to report error for method \(methodName): \(error)")
        }
    }
    
    /// Extract meaningful error message from various error types
    private func extractErrorMessage(from error: Error) -> String {
        // Check for ParaError with custom descriptions
        if let paraError = error as? ParaError {
            return paraError.description
        }
        
        // Check for NSError for more detailed information
        let nsError = error as NSError
        
        // Build detailed message from NSError components
        var components: [String] = []
        
        // Add the main error description if it's not the generic one
        let description = nsError.localizedDescription
        if !description.contains("The operation couldn't be completed") {
            components.append(description)
        }
        
        // Add failure reason if available
        if let failureReason = nsError.localizedFailureReason {
            components.append(failureReason)
        }
        
        // Add recovery suggestion if available
        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
            components.append(recoverySuggestion)
        }
        
        // If we have no meaningful components, at least provide domain and code
        if components.isEmpty {
            components.append("\(nsError.domain) error \(nsError.code)")
        }
        
        // Add underlying error if present
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            components.append("Underlying: \(underlyingError.localizedDescription)")
        }
        
        return components.joined(separator: " - ")
    }
    
    /// Get the iOS version string
    private var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    /// Get the device model name
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        
        // Return the raw model code (e.g., "iPhone15,2")
        // You could map these to friendly names if needed
        return modelCode ?? UIDevice.current.model
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
    let sdkVersion: String
    let environment: String
    let deviceInfo: DeviceInfo
    let userId: String?
}

private struct ErrorInfo: Codable {
    let name: String
    let message: String
}

private struct DeviceInfo: Codable {
    let model: String
    let osVersion: String
}

// MARK: - Error Types

private enum ErrorReportingError: Error {
    case invalidURL
    case networkError
}