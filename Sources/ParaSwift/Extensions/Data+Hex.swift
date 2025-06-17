//
//  Data+Hex.swift
//  ParaSwift
//
//  Created by Para AI on 2/3/25.
//

import Foundation

extension Data {
    /// Initialize Data from a hex string
    /// - Parameter hexString: The hex string (with or without 0x prefix)
    init?(hexString: String) {
        var hex = hexString

        // Remove 0x prefix if present
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        // Ensure even number of characters
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }

        // Convert hex pairs to bytes
        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard nextIndex <= hex.endIndex else { return nil }

            let byteString = String(hex[index ..< nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }

            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
