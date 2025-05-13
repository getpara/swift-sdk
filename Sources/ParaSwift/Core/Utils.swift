import Foundation
import os
import PhoneNumberKit

/// Utility class containing formatting helpers and common operations
public struct ParaFormatting {
    
    /// Formats a phone number into the international format required by Para.
    ///
    /// - Parameters:
    ///   - phoneNumber: The phone number to format.
    ///   - countryCode: Optional country code for the phone number.
    ///   - forDisplay: Whether to format the number for display (with spaces and formatting) or for API (digits only).
    /// - Returns: Formatted phone number in international format, or nil if the number is invalid.
    ///
    /// - Note: This method uses PhoneNumberKit to validate and format phone numbers correctly.
    ///         All Para authentication methods expect phone numbers in international format.
    ///         Example: formatPhoneNumber(phoneNumber: "5551234", countryCode: "1") returns "+15551234".
    public static func formatPhoneNumber(
        phoneNumber: String,
        countryCode: String? = nil,
        forDisplay: Bool = false
    ) -> String? {
        let phoneNumberKit = PhoneNumberUtility()
        
        // Sanitize the phone number by removing non-digit characters
        let sanitizedNumber = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        do {
            let parsedNumber: PhoneNumber
            
            if let countryCode = countryCode {
                // Remove + from country code if present
                let cleanCountryCode = countryCode.hasPrefix("+") ? String(countryCode.dropFirst()) : countryCode
                
                // Parse with provided country code as the default calling code
                parsedNumber = try phoneNumberKit.parse(sanitizedNumber, withRegion: cleanCountryCode, ignoreType: true)
            } else {
                // Add + to the number if not present and parse
                let numberWithPlus = sanitizedNumber.hasPrefix("+") ? sanitizedNumber : "+\(sanitizedNumber)"
                parsedNumber = try phoneNumberKit.parse(numberWithPlus, ignoreType: true)
            }
            
            // Format the phone number according to the forDisplay parameter
            if forDisplay {
                return phoneNumberKit.format(parsedNumber, toType: .international)
            } else {
                // Format for API: remove all non-digit characters except the leading +
                let formattedNumber = phoneNumberKit.format(parsedNumber, toType: .international)
                return formattedNumber.replacingOccurrences(of: "[^\\d+]", with: "", options: .regularExpression)
            }
        } catch {
            return nil
        }
    }
}

@available(macOS 11.0, iOS 14.0, *)
public extension Logger {
    static let authorization = Logger(subsystem: "Para Swift", category: "Passkeys Manager")
    static let capsule = Logger(subsystem: "Para Swift", category: "Para")
}

extension Data {

    /// Instantiates data by decoding a base64url string into base64
    ///
    /// - Parameter string: A base64url encoded string
    init?(base64URLEncoded string: String) {
        self.init(base64Encoded: string.toggleBase64URLSafe(on: false))
    }

    /// Encodes the string into a base64url safe representation
    ///
    /// - Returns: A string that is base64 encoded but made safe for passing
    ///            in as a query parameter into a URL string
    func base64URLEncodedString() -> String {
        return self.base64EncodedString().toggleBase64URLSafe(on: true)
    }

}

extension String {

    /// Encodes or decodes into a base64url safe representation
    ///
    /// - Parameter on: Whether or not the string should be made safe for URL strings
    /// - Returns: if `on`, then a base64url string; if `off` then a base64 string
    func toggleBase64URLSafe(on: Bool) -> String {
        if on {
            // Make base64 string safe for passing into URL query params
            let base64url = self.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "=", with: "")
            return base64url
        } else {
            // Return to base64 encoding
            var base64 = self.replacingOccurrences(of: "_", with: "/")
                .replacingOccurrences(of: "-", with: "+")
            // Add any necessary padding with `=`
            if base64.count % 4 != 0 {
                base64.append(String(repeating: "=", count: 4 - base64.count % 4))
            }
            return base64
        }
    }

}

extension String {
    func fromBase64() -> String? {
        guard let data = Data(base64Encoded: self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func toBase64() -> String {
        return Data(self.utf8).base64EncodedString()
    }

}

extension URL {
    func valueOf(_ queryParameterName: String) -> String? {
        guard let url = URLComponents(string: self.absoluteString) else { return nil }
        return url.queryItems?.first(where: { $0.name == queryParameterName })?.value
    }
}
