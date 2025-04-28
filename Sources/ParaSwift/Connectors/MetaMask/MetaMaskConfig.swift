import Foundation

/// Configuration for MetaMask connection
public struct MetaMaskConfig {
    /// The name of your application
    public let appName: String
    /// Your application's bundle identifier
    public let appId: String
    /// The MetaMask SDK API version to use
    public let apiVersion: String
    
    public init(appName: String, appId: String, apiVersion: String = "1.0") {
        self.appName = appName
        self.appId = appId
        self.apiVersion = apiVersion
    }
} 
