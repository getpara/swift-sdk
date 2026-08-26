import BigInt
import Foundation

enum BridgeSigningValidation {
    static func resolveChainType(
        payloadChainType: BridgeChainType,
        explicitChainType: BridgeChainType?
    ) throws -> BridgeChainType {
        if let explicitChainType, explicitChainType != payloadChainType {
            throw ParaError.error(
                "chainType \(explicitChainType.rawValue) conflicts with the structured payload chainType \(payloadChainType.rawValue)"
            )
        }
        return payloadChainType
    }

    static func resolveChainId(
        chainType: BridgeChainType,
        embeddedChainId: String?,
        explicitChainId: String?
    ) throws -> String? {
        guard let embeddedChainId else { return explicitChainId }
        guard let explicitChainId else { return embeddedChainId }

        let matches: Bool
        switch chainType {
        case .evm:
            matches = try parseEVMChainId(explicitChainId) == parseEVMChainId(embeddedChainId)
        case .cosmos:
            matches = explicitChainId == embeddedChainId
        default:
            matches = true
        }
        guard matches else {
            throw ParaError.error(
                "chainId \(explicitChainId) conflicts with the structured transaction chainId \(embeddedChainId)"
            )
        }
        return explicitChainId
    }

    private static func parseEVMChainId(_ value: String) throws -> BigUInt {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: BigUInt?
        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            parsed = BigUInt(String(normalized.dropFirst(2)), radix: 16)
        } else {
            parsed = BigUInt(normalized, radix: 10)
        }
        guard let parsed else {
            throw ParaError.error("chainId \(value) must be an EVM decimal or 0x-prefixed hexadecimal value")
        }
        return parsed
    }
}
