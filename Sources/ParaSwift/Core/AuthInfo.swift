//
//  AuthInfo.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/11/25.
//

public protocol AuthInfo: Codable {}

public struct EmailAuthInfo: AuthInfo {
    let email: String
    
    public init(email: String) {
        self.email = email
    }
}

public struct PhoneAuthInfo: AuthInfo {
    let phone: String
    let countryCode: String
    
    public init(phone: String, countryCode: String) {
        self.phone = phone
        self.countryCode = countryCode
    }
}
