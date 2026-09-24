//
//  KitoCardDetails.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A payment card network, from the number's leading digits.
public enum KitoCardBrand: String, CaseIterable, Hashable, Sendable {
    case visa, mastercard, amex, discover, jcb, unionPay, diners, unknown

    public var title: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .discover: return "Discover"
        case .jcb: return "JCB"
        case .unionPay: return "UnionPay"
        case .diners: return "Diners Club"
        case .unknown: return "Card"
        }
    }

    /// Digit groups for display: 4-6-5 for Amex, 4-6-4 for Diners, fours otherwise.
    public func groups(forLength length: Int) -> [Int] {
        switch self {
        case .amex where length == 15: return [4, 6, 5]
        case .diners where length == 14: return [4, 6, 4]
        default:
            var groups = Array(repeating: 4, count: length / 4)
            if length % 4 != 0 { groups.append(length % 4) }
            return groups
        }
    }

    /// Identifies the network from the leading digits.
    public static func detect(_ number: String) -> KitoCardBrand {
        let digits = number.filter(\.isNumber)
        func prefix(_ count: Int) -> Int { Int(digits.prefix(count)) ?? -1 }
        if digits.hasPrefix("4") { return .visa }
        if (51...55).contains(prefix(2)) || (2221...2720).contains(prefix(4)) { return .mastercard }
        if [34, 37].contains(prefix(2)) { return .amex }
        if prefix(4) == 6011 || prefix(2) == 65 || (644...649).contains(prefix(3)) { return .discover }
        if (3528...3589).contains(prefix(4)) { return .jcb }
        if prefix(2) == 62 { return .unionPay }
        if prefix(2) == 36 || prefix(2) == 38 || prefix(2) == 39 || (300...305).contains(prefix(3)) { return .diners }
        return .unknown
    }
}

/// A card's expiry month and year.
public struct KitoCardExpiry: Hashable, Sendable, Comparable {
    public let month: Int
    public let year: Int

    public init?(month: Int, year: Int) {
        guard (1...12).contains(month), (2000...2099).contains(year) else { return nil }
        self.month = month
        self.year = year
    }

    /// "08/27"
    public var formatted: String { String(format: "%02d/%02d", month, year % 100) }

    /// Cards are valid through the last day of their expiry month.
    public func isExpired(on date: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return false }
        return (year, month) > (self.year, self.month)
    }

    public static func < (lhs: KitoCardExpiry, rhs: KitoCardExpiry) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// Every `MM/YY`, `MM/YYYY` or `MM-YY` date in the text, in order.
    public static func all(in text: String) -> [KitoCardExpiry] {
        let pattern = #"(?<![0-9])(0[1-9]|1[0-2])\s?[/\-]\s?([0-9]{4}|[0-9]{2})(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let monthRange = Range(match.range(at: 1), in: text), let yearRange = Range(match.range(at: 2), in: text),
                  let month = Int(text[monthRange]), let rawYear = Int(text[yearRange]) else { return nil }
            return KitoCardExpiry(month: month, year: rawYear < 100 ? 2000 + rawYear : rawYear)
        }
    }

    /// The expiry printed on a card. When there are several dates ("VALID FROM 01/23 THRU
    /// 01/28") it's the latest.
    public static func parse(_ text: String) -> KitoCardExpiry? {
        all(in: text).max()
    }
}

/// What `KitoCardScanner` reads off a card. The full number is never kept: only the last four
/// digits, a masked form and whether it passed the Luhn check.
public struct KitoCardDetails: Hashable, Sendable {
    public let brand: KitoCardBrand
    public let last4: String
    /// e.g. "•••• •••• •••• 4242"
    public let maskedNumber: String
    public let isNumberValid: Bool
    public let expiry: KitoCardExpiry?
    public let holderName: String?

    public init(brand: KitoCardBrand, last4: String, maskedNumber: String, isNumberValid: Bool, expiry: KitoCardExpiry?, holderName: String?) {
        self.brand = brand
        self.last4 = last4
        self.maskedNumber = maskedNumber
        self.isNumberValid = isNumberValid
        self.expiry = expiry
        self.holderName = holderName
    }

    /// Builds details from a full number, keeping only the masked parts.
    public init(number: String, expiry: KitoCardExpiry? = nil, holderName: String? = nil) {
        let digits = number.filter(\.isNumber)
        let brand = KitoCardBrand.detect(digits)
        self.brand = brand
        self.last4 = String(digits.suffix(4))
        self.maskedNumber = KitoCardMask.mask(digits, brand: brand)
        self.isNumberValid = KitoCheckDigits.isValidLuhn(digits)
        self.expiry = expiry
        self.holderName = holderName
    }
}

/// Masks card numbers for display.
public enum KitoCardMask {
    /// "4242424242424242" → "•••• •••• •••• 4242", grouped the way the brand prints it.
    public static func mask(_ number: String, brand: KitoCardBrand? = nil, visible: Int = 4) -> String {
        let digits = Array(number.filter(\.isNumber))
        guard !digits.isEmpty else { return "" }
        let shown = min(visible, digits.count)
        let masked = digits.enumerated().map { index, digit in index < digits.count - shown ? "•" : String(digit) }
        let groups = (brand ?? KitoCardBrand.detect(String(digits))).groups(forLength: digits.count)
        var result: [String] = []
        var cursor = 0
        for size in groups where cursor < masked.count {
            let end = min(cursor + size, masked.count)
            result.append(masked[cursor..<end].joined())
            cursor = end
        }
        return result.joined(separator: " ")
    }
}

/// Pulls card details out of recognised text lines (from `VNRecognizeTextRequest` or any OCR).
public enum KitoCardTextParser {
    /// Words that appear on cards but are never the holder's name.
    static let stopWords: Set<String> = [
        "VALID", "THRU", "FROM", "UNTIL", "EXPIRES", "EXP", "EXPIRY", "GOOD", "MONTH", "YEAR", "MEMBER", "SINCE",
        "DEBIT", "CREDIT", "CARD", "BANK", "VISA", "MASTERCARD", "PLATINUM", "GOLD", "CLASSIC", "WORLD", "SIGNATURE",
        "ELECTRON", "BUSINESS", "PREPAID", "INFINITE", "CONTACTLESS", "AMERICAN", "EXPRESS", "DISCOVER", "UNIONPAY",
        "INTERNATIONAL", "ELITE", "REWARDS", "AUTHORIZED", "CUSTOMER", "SERVICE", "WWW", "COM", "KES", "LTD", "PLC",
    ]

    /// Reads the number (Luhn-checked), expiry and name. Nil when no valid number is found.
    public static func details(from lines: [String]) -> KitoCardDetails? {
        var numberLine: Int?
        var number: String?
        for (index, line) in lines.enumerated() {
            if let candidate = cardNumber(in: line) { number = candidate; numberLine = index; break }
        }
        // Some cards split the number over two lines of OCR.
        if number == nil {
            for index in lines.indices.dropLast() {
                if let candidate = cardNumber(in: lines[index] + " " + lines[index + 1]) { number = candidate; numberLine = index + 1; break }
            }
        }
        guard let number else { return nil }
        let expiry = KitoCardExpiry.parse(lines.joined(separator: " "))
        let name = holderName(in: lines, after: numberLine)
        return KitoCardDetails(number: number, expiry: expiry, holderName: name)
    }

    /// The first 13–19 digit run in the line that passes Luhn, with common OCR slips fixed.
    static func cardNumber(in line: String) -> String? {
        let pattern = #"(?:[0-9OoIlSB|][ \-]?){12,18}[0-9OoIlSB|]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        for match in regex.matches(in: line, range: range) {
            guard let matchRange = Range(match.range, in: line) else { continue }
            let candidate = normalizeDigits(String(line[matchRange]))
            let realDigits = line[matchRange].filter(\.isNumber).count
            guard (13...19).contains(candidate.count), realDigits * 4 >= candidate.count * 3 else { continue }
            if KitoCheckDigits.isValidLuhn(candidate) { return candidate }
        }
        return nil
    }

    /// Maps letters OCR often confuses with digits, and drops separators.
    static func normalizeDigits(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "O", "o": result.append("0")
            case "I", "l", "|": result.append("1")
            case "S": result.append("5")
            case "B": result.append("8")
            case " ", "-": continue
            default: result.append(character)
            }
        }
        return result
    }

    /// The most name-like line: two to four alphabetic words, mostly capitals, no card words.
    /// Prefers lines after the number, where most cards print the name.
    static func holderName(in lines: [String], after numberLine: Int?) -> String? {
        let candidates = lines.enumerated().filter { isNameLike($0.element) }
        let preferred = candidates.first { candidate in numberLine.map { candidate.offset > $0 } ?? true } ?? candidates.first
        return preferred.map { titleCased($0.element) }
    }

    static func isNameLike(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard (4...28).contains(trimmed.count), trimmed.allSatisfy({ $0.isLetter || " .'-".contains($0) }) else { return false }
        let words = trimmed.split(separator: " ").map { $0.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        guard (2...4).contains(words.count), words.allSatisfy({ !$0.isEmpty }) else { return false }
        guard !words.contains(where: { stopWords.contains($0) }) else { return false }
        let letters = trimmed.filter(\.isLetter)
        let capitals = letters.filter(\.isUppercase).count
        return capitals * 10 >= letters.count * 6
    }

    /// "ACHIENG W OWUOR" → "Achieng W Owuor"
    static func titleCased(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces).split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
