//
//  KitoCheckDigits.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Check-digit maths for product barcodes (GS1 mod 10) and card numbers (Luhn). Pure.
public enum KitoCheckDigits {
    /// The GS1 check digit for the digits before it (EAN-8, UPC-A, EAN-13, GTIN-14 bodies).
    /// Weights alternate 3, 1, 3… starting from the rightmost digit.
    public static func gtinCheckDigit(for body: String) -> Int? {
        let digits = body.compactMap(\.wholeNumberValue)
        guard !digits.isEmpty, digits.count == body.count else { return nil }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    /// Whether an 8, 12, 13 or 14 digit GTIN ends in the right check digit.
    public static func isValidGTIN(_ code: String) -> Bool {
        guard [8, 12, 13, 14].contains(code.count), let last = code.last?.wholeNumberValue,
              let expected = gtinCheckDigit(for: String(code.dropLast())) else { return false }
        return last == expected
    }

    /// Expands an 8-digit UPC-E (number system, six digits, check) to its 12-digit UPC-A.
    public static func expandUPCE(_ code: String) -> String? {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == 8, digits.count == code.count, digits[0] == 0 || digits[0] == 1 else { return nil }
        let d = Array(digits[1...6])
        let body: [Int]
        switch d[5] {
        case 0, 1, 2: body = [d[0], d[1], d[5], 0, 0, 0, 0, d[2], d[3], d[4]]
        case 3: body = [d[0], d[1], d[2], 0, 0, 0, 0, 0, d[3], d[4]]
        case 4: body = [d[0], d[1], d[2], d[3], 0, 0, 0, 0, 0, d[4]]
        default: body = [d[0], d[1], d[2], d[3], d[4], 0, 0, 0, 0, d[5]]
        }
        return ([digits[0]] + body + [digits[7]]).map(String.init).joined()
    }

    /// Whether a UPC-E's check digit matches its expanded UPC-A.
    public static func isValidUPCE(_ code: String) -> Bool {
        guard let expanded = expandUPCE(code) else { return false }
        return isValidGTIN(expanded)
    }

    /// Adds the GS1 check digit, e.g. "616100123456" → "6161001234565".
    public static func appendingGTINCheckDigit(to body: String) -> String? {
        gtinCheckDigit(for: body).map { body + String($0) }
    }

    /// The Luhn check used by card numbers. Ignores spaces and dashes.
    public static func isValidLuhn(_ number: String) -> Bool {
        let cleaned = number.filter { $0 != " " && $0 != "-" }
        let digits = cleaned.compactMap(\.wholeNumberValue)
        guard digits.count >= 2, digits.count == cleaned.count else { return false }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum % 10 == 0
    }

    /// The Luhn check digit for the digits before it.
    public static func luhnCheckDigit(for body: String) -> Int? {
        guard !body.isEmpty, body.allSatisfy(\.isNumber) else { return nil }
        for candidate in 0...9 where isValidLuhn(body + String(candidate)) { return candidate }
        return nil
    }

    /// A handful of GS1 prefixes, with East Africa covered.
    static func gs1Region(forEAN13 code: String) -> String? {
        guard code.count == 13, let prefix = Int(code.prefix(3)) else { return nil }
        switch prefix {
        case 0...19, 30...39, 60...139: return "USA / Canada"
        case 300...379: return "France"
        case 400...440: return "Germany"
        case 450...459, 490...499: return "Japan"
        case 500...509: return "United Kingdom"
        case 600...601: return "South Africa"
        case 603: return "Ghana"
        case 615: return "Nigeria"
        case 616: return "Kenya"
        case 618: return "Ivory Coast"
        case 620: return "Tanzania"
        case 629: return "United Arab Emirates"
        case 690...699: return "China"
        case 890: return "India"
        default: return nil
        }
    }
}
