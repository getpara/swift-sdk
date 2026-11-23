import Foundation

/// Represents the originator information required by MetaMask
struct OriginatorInfo: Codable {
    private struct Payload: Codable {
        let originatorInfo: Info
        let type: String
        let originator: Info

        init(originatorInfo: Info, originator: Info) {
            self.originatorInfo = originatorInfo
            type = "originator_info"
            self.originator = originator
        }

        struct Info: Codable {
            let url: String
            let apiVersion: String
            let platform: String
            let title: String
            let dappId: String
        }
    }

    let url: String
    let apiVersion: String
    let platform: String
    let title: String
    let dappId: String

    // Encodes the originator info in MetaMask's expected format
    func encode() throws -> String {
        let info = Payload.Info(
            url: url,
            apiVersion: apiVersion,
            platform: platform,
            title: title,
            dappId: dappId,
        )
        let payload = Payload(originatorInfo: info, originator: info)
        let data = try JSONEncoder().encode(payload)
        return data.base64EncodedString()
    }
}

/// Request parameters for signing messages
struct SignMessageRequest: Codable {
    /// JSON-RPC id. MetaMask echoes it in its reply, which ties the reply to this request.
    let id: String
    let params: [String]
    let method: String

    init(id: String, params: [String]) {
        self.id = id
        self.params = params
        method = "personal_sign"
    }

    func encode() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }
}

/// Request parameters for sending transactions
struct SendTransactionRequest: Codable {
    /// JSON-RPC id. MetaMask echoes it in its reply, which ties the reply to this request.
    let id: String
    let params: [[String: String]]
    let method: String

    init(id: String, params: [[String: String]]) {
        self.id = id
        self.params = params
        method = "eth_sendTransaction"
    }

    func encode() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data.base64EncodedString()
    }
}
