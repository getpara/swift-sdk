import BigInt
import Foundation

/// Checks that a `personal_sign` (EIP-191) signature was produced by a given account.
///
/// Verification only: nothing here handles private keys.
enum PersonalSignVerifier {
    /// Whether `signature` is a `personal_sign` signature of `message` by `account`.
    ///
    /// Wallets sign a `0x`-prefixed hex message as raw bytes and anything else as UTF-8 text. Both readings are
    /// accepted, because either way only the account's key can produce the signature.
    static func isValid(signature: String, message: String, account: String) -> Bool {
        guard let expected = bytes(fromHex: account), expected.count == 20 else { return false }

        var payloads = [Data(message.utf8)]
        if let raw = bytes(fromHex: message) {
            payloads.append(raw)
        }
        return payloads.contains { recoverSigner(payload: $0, signature: signature) == expected }
    }

    /// The 20-byte address that signed `payload` with `personal_sign`, or nil when the signature is malformed.
    static func recoverSigner(payload: Data, signature: String) -> Data? {
        guard let sig = bytes(fromHex: signature), sig.count == 65 else { return nil }
        let recoveryId: UInt8
        switch sig[64] {
        case 0, 1: recoveryId = sig[64]
        case 27, 28: recoveryId = sig[64] - 27
        default: return nil
        }

        let prefix = Data("\u{19}Ethereum Signed Message:\n\(payload.count)".utf8)
        let digest = Keccak256.hash(prefix + payload)

        guard let publicKey = Secp256k1.recover(
            digest: BigUInt(digest),
            r: BigUInt(sig.subdata(in: 0 ..< 32)),
            s: BigUInt(sig.subdata(in: 32 ..< 64)),
            oddY: recoveryId == 1,
        ) else { return nil }

        let encoded = leftPadded(publicKey.x.serialize(), to: 32) + leftPadded(publicKey.y.serialize(), to: 32)
        return Keccak256.hash(encoded).suffix(20)
    }

    /// Whether `value` is a `0x`-prefixed 20-byte hex address.
    static func isAddress(_ value: String) -> Bool {
        bytes(fromHex: value)?.count == 20
    }

    /// Decodes a `0x`-prefixed, even-length hex string. Returns nil for anything else.
    static func bytes(fromHex value: String) -> Data? {
        guard value.hasPrefix("0x") || value.hasPrefix("0X") else { return nil }
        let digits = Array(value.utf8.dropFirst(2))
        guard digits.count % 2 == 0 else { return nil }

        var data = Data(capacity: digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = hexValue(digits[index]), let low = hexValue(digits[index + 1]) else { return nil }
            data.append(high << 4 | low)
        }
        return data
    }

    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    private static func leftPadded(_ data: Data, to length: Int) -> Data {
        data.count >= length ? data : Data(repeating: 0, count: length - data.count) + data
    }
}

/// Public-key recovery on secp256k1 (no signing, no secret inputs).
enum Secp256k1 {
    struct Point: Equatable {
        let x: BigUInt
        let y: BigUInt
    }

    static let p = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", radix: 16)!
    static let n = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!
    static let g = Point(
        x: BigUInt("79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", radix: 16)!,
        y: BigUInt("483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", radix: 16)!,
    )

    /// Recovers the public key Q = r⁻¹(sR − eG), where R is the curve point with x = r and the given y parity.
    static func recover(digest: BigUInt, r: BigUInt, s: BigUInt, oddY: Bool) -> Point? {
        guard r > 0, r < n, s > 0, s < n else { return nil }

        // y² = x³ + 7; p ≡ 3 (mod 4), so a square root is (x³ + 7)^((p + 1) / 4).
        let ySquared = (r.power(3, modulus: p) + 7) % p
        var y = ySquared.power((p + 1) / 4, modulus: p)
        guard (y * y) % p == ySquared else { return nil }
        if (y % 2 == 1) != oddY {
            y = p - y
        }

        guard let rInverse = r.inverse(n) else { return nil }
        let u1 = (n - digest % n) * rInverse % n
        let u2 = s * rInverse % n
        return combine(u1, g, u2, Point(x: r, y: y))
    }

    // Jacobian coordinates (x = X / Z², y = Y / Z³), so the loop needs no modular inversions. Z = 0 is the point
    // at infinity.
    private struct Jacobian {
        var x: BigUInt
        var y: BigUInt
        var z: BigUInt

        static let infinity = Jacobian(x: 1, y: 1, z: 0)

        init(x: BigUInt, y: BigUInt, z: BigUInt) {
            self.x = x
            self.y = y
            self.z = z
        }

        init(_ point: Point) {
            self.init(x: point.x, y: point.y, z: 1)
        }
    }

    private static func mul(_ lhs: BigUInt, _ rhs: BigUInt) -> BigUInt {
        lhs * rhs % p
    }

    private static func sub(_ lhs: BigUInt, _ rhs: BigUInt) -> BigUInt {
        lhs >= rhs ? lhs - rhs : lhs + p - rhs
    }

    private static func double(_ point: Jacobian) -> Jacobian {
        guard point.z != 0, point.y != 0 else { return .infinity }
        let ySquared = mul(point.y, point.y)
        let s = mul(4, mul(point.x, ySquared))
        let m = mul(3, mul(point.x, point.x))
        let x = sub(mul(m, m), mul(2, s))
        let y = sub(mul(m, sub(s, x)), mul(8, mul(ySquared, ySquared)))
        return Jacobian(x: x, y: y, z: mul(2, mul(point.y, point.z)))
    }

    private static func add(_ lhs: Jacobian, _ rhs: Jacobian) -> Jacobian {
        guard lhs.z != 0 else { return rhs }
        guard rhs.z != 0 else { return lhs }

        let lhsZ2 = mul(lhs.z, lhs.z)
        let rhsZ2 = mul(rhs.z, rhs.z)
        let u1 = mul(lhs.x, rhsZ2)
        let u2 = mul(rhs.x, lhsZ2)
        let s1 = mul(lhs.y, mul(rhsZ2, rhs.z))
        let s2 = mul(rhs.y, mul(lhsZ2, lhs.z))
        if u1 == u2 {
            return s1 == s2 ? double(lhs) : .infinity
        }

        let h = sub(u2, u1)
        let r = sub(s2, s1)
        let h2 = mul(h, h)
        let h3 = mul(h, h2)
        let v = mul(u1, h2)
        let x = sub(sub(mul(r, r), h3), mul(2, v))
        let y = sub(mul(r, sub(v, x)), mul(s1, h3))
        return Jacobian(x: x, y: y, z: mul(h, mul(lhs.z, rhs.z)))
    }

    /// Computes a·P + b·Q with one shared double-and-add pass.
    private static func combine(_ a: BigUInt, _ pointP: Point, _ b: BigUInt, _ pointQ: Point) -> Point? {
        let first = Jacobian(pointP)
        let second = Jacobian(pointQ)
        let both = add(first, second)

        var result = Jacobian.infinity
        for bit in stride(from: max(a.bitWidth, b.bitWidth) - 1, through: 0, by: -1) {
            result = double(result)
            switch (a >> bit & 1 == 1, b >> bit & 1 == 1) {
            case (true, true): result = add(result, both)
            case (true, false): result = add(result, first)
            case (false, true): result = add(result, second)
            case (false, false): break
            }
        }

        guard result.z != 0, let zInverse = result.z.inverse(p) else { return nil }
        let zInverse2 = mul(zInverse, zInverse)
        return Point(x: mul(result.x, zInverse2), y: mul(result.y, mul(zInverse2, zInverse)))
    }
}

/// Keccak-256 as used by Ethereum (original Keccak padding, not SHA3-256).
enum Keccak256 {
    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]
    private static let rotations: [UInt64] = [
        1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44,
    ]
    private static let lanes: [Int] = [
        10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
    ]
    private static let rate = 136

    static func hash(_ input: Data) -> Data {
        var message = [UInt8](input)
        message.append(0x01)
        while message.count % rate != 0 {
            message.append(0x00)
        }
        message[message.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        for block in stride(from: 0, to: message.count, by: rate) {
            for lane in 0 ..< rate / 8 {
                var word: UInt64 = 0
                for byte in 0 ..< 8 {
                    word |= UInt64(message[block + lane * 8 + byte]) << UInt64(8 * byte)
                }
                state[lane] ^= word
            }
            permute(&state)
        }

        var output = Data(capacity: 32)
        for lane in 0 ..< 4 {
            for byte in 0 ..< 8 {
                output.append(UInt8(truncatingIfNeeded: state[lane] >> UInt64(8 * byte)))
            }
        }
        return output
    }

    private static func permute(_ state: inout [UInt64]) {
        var columns = [UInt64](repeating: 0, count: 5)
        for round in 0 ..< 24 {
            for x in 0 ..< 5 {
                columns[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }
            for x in 0 ..< 5 {
                let mix = columns[(x + 4) % 5] ^ rotateLeft(columns[(x + 1) % 5], by: 1)
                for y in stride(from: 0, to: 25, by: 5) {
                    state[x + y] ^= mix
                }
            }

            var carried = state[1]
            for index in 0 ..< 24 {
                let lane = lanes[index]
                let next = state[lane]
                state[lane] = rotateLeft(carried, by: rotations[index])
                carried = next
            }

            for y in stride(from: 0, to: 25, by: 5) {
                let row = Array(state[y ..< y + 5])
                for x in 0 ..< 5 {
                    state[y + x] = row[x] ^ (~row[(x + 1) % 5] & row[(x + 2) % 5])
                }
            }

            state[0] ^= roundConstants[round]
        }
    }

    private static func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
        value << amount | value >> (64 - amount)
    }
}
