import Foundation

public enum ParaEnvironment: Hashable {
    case dev(relyingPartyId: String, jsBridgeUrl: URL?)
    case sandbox
    case beta
    case prod
    
    private var config: (relyingPartyId: String, jsBridgeUrl: URL, name: String) {
        switch self {
        case .dev(let relyingPartyId, let jsBridgeUrl):
            return (
                relyingPartyId,
                jsBridgeUrl ?? URL(string: "http://localhost:5173")!,
                "DEV"
            )
        case .sandbox:
            return (
                "app.sandbox.usecapsule.com",
                URL(string: "https://alpha-js-bridge.sandbox.getpara.com/")!,
                "SANDBOX"
            )
        case .beta:
            return (
                "app.beta.usecapsule.com",
                URL(string: "https://js-bridge.beta.usecapsule.com/")!,
                "BETA"
            )
        case .prod:
            return (
                "app.usecapsule.com",
                URL(string: "https://js-bridge.prod.usecapsule.com/")!,
                "PROD"
            )
        }
    }
    
    var relyingPartyId: String {
        config.relyingPartyId
    }
    
    var jsBridgeUrl: URL {
        config.jsBridgeUrl
    }
    
    var name: String {
        config.name
    }
}
