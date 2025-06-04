import Foundation

public enum ParaEnvironment: Hashable {
    case dev(relyingPartyId: String, jsBridgeUrl: URL?)
    case sandbox
    case beta
    case prod

    private var config: (relyingPartyId: String, jsBridgeUrl: URL, name: String) {
        switch self {
        case let .dev(relyingPartyId, jsBridgeUrl):
            (
                relyingPartyId,
                jsBridgeUrl ?? URL(string: "http://localhost:5173")!,
                "DEV"
            )
        case .sandbox:
            (
                "app.sandbox.usecapsule.com",
                URL(string: "https://alpha-js-bridge.sandbox.getpara.com/")!,
                "SANDBOX"
            )
        case .beta:
            (
                "app.beta.usecapsule.com",
                URL(string: "https://js-bridge.beta.usecapsule.com/")!,
                "BETA"
            )
        case .prod:
            (
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
