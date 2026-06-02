import Foundation

public enum StellarAddressError: Error, LocalizedError {
    case invalidHexPublicKey
    case invalidBase58Character(Character)
    case invalidPublicKeyLength(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidHexPublicKey:
            "Invalid hex public key"
        case let .invalidBase58Character(character):
            "Invalid base58 character: \(character)"
        case let .invalidPublicKeyLength(length):
            "Invalid Ed25519 public key length: expected 32 bytes, got \(length)"
        }
    }
}

public enum StellarAddress {
    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let versionByte = UInt8(6 << 3)

    public static func fromPublicKey(_ publicKey: String) throws -> String {
        guard !publicKey.isEmpty else { return "" }
        return try encodeEd25519PublicKey(hexDecode(publicKey))
    }

    public static func fromSolanaAddress(_ solanaAddress: String) throws -> String {
        guard !solanaAddress.isEmpty else { return "" }
        return try encodeEd25519PublicKey(base58Decode(solanaAddress))
    }

    private static func hexDecode(_ value: String) throws -> [UInt8] {
        let normalized = value.hasPrefix("0x") || value.hasPrefix("0X") ? String(value.dropFirst(2)) : value
        guard !normalized.isEmpty, normalized.count.isMultiple(of: 2) else {
            throw StellarAddressError.invalidHexPublicKey
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)
        var index = normalized.startIndex

        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index ..< nextIndex], radix: 16) else {
                throw StellarAddressError.invalidHexPublicKey
            }
            bytes.append(byte)
            index = nextIndex
        }

        return bytes
    }

    private static func base58Decode(_ value: String) throws -> [UInt8] {
        var bytes = [UInt8(0)]

        for character in value {
            guard let digit = base58Alphabet.firstIndex(of: character) else {
                throw StellarAddressError.invalidBase58Character(character)
            }

            var carry = digit
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xff)
                carry >>= 8
            }

            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        let leadingZeros = value.prefix { $0 == "1" }.count
        var significantBytes = bytes.count
        while significantBytes > 0, bytes[significantBytes - 1] == 0 {
            significantBytes -= 1
        }

        var result = Array(repeating: UInt8(0), count: leadingZeros + significantBytes)
        for index in 0 ..< significantBytes {
            result[leadingZeros + significantBytes - 1 - index] = bytes[index]
        }
        return result
    }

    private static func encodeEd25519PublicKey(_ publicKeyBytes: [UInt8]) throws -> String {
        guard publicKeyBytes.count == 32 else {
            throw StellarAddressError.invalidPublicKeyLength(publicKeyBytes.count)
        }

        let payload = [versionByte] + publicKeyBytes
        let checksum = crc16XModem(payload)
        let full = payload + [UInt8(checksum & 0xff), UInt8((checksum >> 8) & 0xff)]
        return base32Encode(full)
    }

    private static func crc16XModem(_ bytes: [UInt8]) -> UInt16 {
        var crc = UInt32(0)
        for byte in bytes {
            crc ^= UInt32(byte) << 8
            for _ in 0 ..< 8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
                crc &= 0xffff
            }
        }
        return UInt16(crc)
    }

    private static func base32Encode(_ bytes: [UInt8]) -> String {
        var result = ""
        var bits = 0
        var value = 0

        for byte in bytes {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                result.append(base32Alphabet[(value >> (bits - 5)) & 0x1f])
                bits -= 5
            }
        }

        if bits > 0 {
            result.append(base32Alphabet[(value << (5 - bits)) & 0x1f])
        }
        return result
    }
}

public extension Wallet {
    var stellarAddress: String? {
        if let publicKey {
            return try? StellarAddress.fromPublicKey(publicKey)
        }
        if let address {
            return try? StellarAddress.fromSolanaAddress(address)
        }
        return nil
    }
}
