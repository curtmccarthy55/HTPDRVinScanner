//
//  CJMVinValidator.swift
//  CJMVinScanner
//
//  Created by Curtis McCarthy on 5/28/22.
//

import Foundation

/// Provides logic to verify that a scanned code is a valid VIN.
struct CJMVinValidator {
    /// Checks if potential VIN string is long enough, then cleans any illegal characters.
    /// - Parameter code: The potential VIN code to check.
    /// - Returns: The potential VIN code cleared of leading characters.
    static func sanitizePossibleVIN(code: String?) -> String? {
        guard let component = code, component.count >= 17 else { return nil }
        
        var sanitizedCode: String?
        if component.contains("I") {
            #if DEBUG
            print("sanitizing code: \(component)")
            #endif
            sanitizedCode = component.replacingOccurrences(of: "I", with: "")
        } else {
            sanitizedCode = component
        }
        
        return sanitizedCode
    }
    
    /// Determines if the given string is a valid VIN code.
    static func isValidVIN(code: String) -> Bool {
        if code.count < 17 {
            // VIN code too short.
            return false
        }
        
        let validLetters = "[ABCDEFGHJKLMNPRSTUVWXYZ0-9a-z]*"
        let myTest = NSPredicate(format: "SELF MATCHES %@", validLetters)
        let valid = myTest.evaluate(with: code)
        
        return valid
    }
}
