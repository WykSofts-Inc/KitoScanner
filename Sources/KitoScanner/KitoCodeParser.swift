//
//  KitoCodeParser.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Turns the raw string inside a QR code or barcode into a typed `KitoCodePayload`.
/// Pure and synchronous, so it's safe to call anywhere.
public enum KitoCodeParser {
    /// The URL scheme `KitoPaymentRequest` uses.
    public static let paymentScheme = "kitopay"

    /// Parses a raw code. Anything it doesn't recognise comes back as `.text`.
    public static func parse(_ raw: String, symbology: KitoSymbology? = nil) -> KitoCodePayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = text.uppercased()

        if let product = product(text, symbology: symbology) { return .product(product) }
        if upper.hasPrefix("WIFI:"), let network = wifi(text) { return .wifi(network) }
        if upper.hasPrefix("MECARD:"), let card = mecard(text) { return .contact(card) }
        if upper.hasPrefix("BEGIN:VCARD"), let card = vCard(text) { return .contact(card) }
        if upper.hasPrefix("BEGIN:VEVENT") || upper.hasPrefix("BEGIN:VCALENDAR"), let event = event(text) { return .event(event) }
        if upper.hasPrefix("\(paymentScheme.uppercased()):"), let payment = payment(text) { return .payment(payment) }
        if upper.hasPrefix("TEL:"), let number = phone(String(text.dropFirst(4))) { return .phone(number) }
        if upper.hasPrefix("MAILTO:"), let message = mailto(text) { return .email(message) }
        if upper.hasPrefix("MATMSG:"), let message = matmsg(text) { return .email(message) }
        if upper.hasPrefix("SMSTO:") || upper.hasPrefix("SMS:"), let message = sms(text) { return .sms(message) }
        if upper.hasPrefix("GEO:"), let point = geo(text) { return .geo(point) }
        if let url = webURL(text) { return .url(url) }
        if isEmailAddress(text) { return .email(KitoEmailMessage(address: text)) }
        if text.hasPrefix("+"), let number = phone(text) { return .phone(number) }
        return .text(text)
    }

    // MARK: Products

    static func product(_ text: String, symbology: KitoSymbology?) -> KitoProductCode? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if let symbology, !KitoSymbology.retail.contains(symbology), symbology != .itf14 { return nil }
        switch text.count {
        case 8: return KitoProductCode(digits: text, kind: symbology == .upce ? .upcE : .ean8)
        case 12: return KitoProductCode(digits: text, kind: .upcA)
        case 13: return KitoProductCode(digits: text, kind: .ean13)
        case 14: return KitoProductCode(digits: text, kind: .gtin14)
        default: return nil
        }
    }

    // MARK: Wi-Fi, MECARD, MATMSG

    static func wifi(_ text: String) -> KitoWiFiNetwork? {
        let fields = keyedFields(String(text.dropFirst(5)))
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let type = (fields["T"] ?? "").uppercased()
        let password = fields["P"].flatMap { $0.isEmpty ? nil : $0 }
        let security: KitoWiFiNetwork.Security
        switch type {
        case "WEP": security = .wep
        case "", "NOPASS", "NONE": security = password == nil ? .open : .wpa
        default: security = .wpa
        }
        let hidden = (fields["H"] ?? "").lowercased() == "true"
        return KitoWiFiNetwork(ssid: ssid, password: security == .open ? nil : password, security: security, isHidden: hidden)
    }

    static func mecard(_ text: String) -> KitoContactCard? {
        let pairs = keyedFieldList(String(text.dropFirst(7)))
        var card = KitoContactCard(name: "")
        for (key, value) in pairs where !value.isEmpty {
            switch key {
            case "N":
                let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                card.name = parts.count == 2 ? "\(parts[1]) \(parts[0])" : value
            case "TEL": card.phones.append(value)
            case "EMAIL": card.emails.append(value)
            case "ORG": card.organization = value
            case "TITLE": card.jobTitle = value
            case "ADR": card.address = value
            case "URL": card.website = value
            case "NOTE": card.note = value
            default: break
            }
        }
        if card.name.isEmpty { card.name = card.organization ?? card.phones.first ?? card.emails.first ?? "" }
        return card.name.isEmpty ? nil : card
    }

    static func matmsg(_ text: String) -> KitoEmailMessage? {
        let fields = keyedFields(String(text.dropFirst(7)))
        guard let address = fields["TO"], !address.isEmpty else { return nil }
        return KitoEmailMessage(address: address, subject: fields["SUB"].flatMap(nonEmpty), body: fields["BODY"].flatMap(nonEmpty))
    }

    /// Splits `K:V;K:V;;` into pairs, honouring `\` escapes, keeping repeated keys.
    static func keyedFieldList(_ text: String) -> [(String, String)] {
        splitEscaped(text, on: ";").compactMap { field in
            guard let colon = field.firstIndex(of: ":") else { return nil }
            let key = field[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            return key.isEmpty ? nil : (key, String(field[field.index(after: colon)...]))
        }
    }

    static func keyedFields(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in keyedFieldList(text) where result[key] == nil { result[key] = value }
        return result
    }

    /// Splits on `separator` except where it's backslash-escaped, and removes the escapes. A
    /// field's key never contains an escape, so its first `:` is still the key separator.
    static func splitEscaped(_ text: String, on separator: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var escaping = false
        for character in text {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == separator {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { fields.append(current) }
        return fields
    }

    /// Escapes `\ ; , : "` for `WIFI:` and `MECARD:` strings.
    public static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            if "\\;,:\"".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    // MARK: vCard and iCalendar

    /// Content lines with folding undone: `KEY;PARAM=X:value` → (KEY, [PARAM=X], value).
    static func contentLines(_ text: String) -> [(name: String, params: [String], value: String)] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var unfolded: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t", !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += line.dropFirst()
            } else if !line.isEmpty {
                unfolded.append(line)
            }
        }
        return unfolded.compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let head = line[..<colon].split(separator: ";").map(String.init)
            guard let name = head.first?.uppercased() else { return nil }
            // "item1.TEL" style groups.
            let bare = name.split(separator: ".").last.map(String.init) ?? name
            return (bare, Array(head.dropFirst()), String(line[line.index(after: colon)...]))
        }
    }

    static func unescapeICS(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                result.append(character == "n" || character == "N" ? "\n" : character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    public static func escapeICS(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func vCard(_ text: String) -> KitoContactCard? {
        var card = KitoContactCard(name: "")
        var structuredName: String?
        for line in contentLines(text) {
            let value = unescapeICS(line.value)
            guard !value.isEmpty else { continue }
            switch line.name {
            case "FN": card.name = value
            case "N": structuredName = structuredNameText(line.value)
            case "TEL": card.phones.append(value)
            case "EMAIL": card.emails.append(value)
            case "ORG": card.organization = unescapeICS(line.value.split(separator: ";").first.map(String.init) ?? line.value)
            case "TITLE": card.jobTitle = value
            case "ADR": card.address = addressText(line.value)
            case "URL": card.website = value
            case "NOTE": card.note = value
            default: break
            }
        }
        if card.name.isEmpty { card.name = structuredName ?? card.organization ?? card.phones.first ?? "" }
        return card.name.isEmpty ? nil : card
    }

    /// "Owuor;Achieng;;Dr.;" → "Dr. Achieng Owuor"
    static func structuredNameText(_ value: String) -> String? {
        let parts = value.components(separatedBy: ";").map { unescapeICS($0) }
        func part(_ index: Int) -> String { index < parts.count ? parts[index] : "" }
        let ordered = [part(3), part(1), part(2), part(0), part(4)].filter { !$0.isEmpty }
        return ordered.isEmpty ? nil : ordered.joined(separator: " ")
    }

    /// ";;Kenyatta Ave 12;Nairobi;;00100;Kenya" → "Kenyatta Ave 12, Nairobi, 00100, Kenya"
    static func addressText(_ value: String) -> String? {
        let parts = value.components(separatedBy: ";").map { unescapeICS($0) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func event(_ text: String) -> KitoScannedEvent? {
        var event = KitoScannedEvent(title: "")
        var inEvent = !text.uppercased().hasPrefix("BEGIN:VCALENDAR")
        for line in contentLines(text) {
            if line.name == "BEGIN", line.value.uppercased() == "VEVENT" { inEvent = true; continue }
            if line.name == "END", line.value.uppercased() == "VEVENT" { break }
            guard inEvent else { continue }
            switch line.name {
            case "SUMMARY": event.title = unescapeICS(line.value)
            case "LOCATION": event.location = nonEmpty(unescapeICS(line.value))
            case "DESCRIPTION": event.notes = nonEmpty(unescapeICS(line.value))
            case "DTSTART":
                if let parsed = icsDate(line.value) { event.start = parsed.date; event.isAllDay = parsed.allDay }
            case "DTEND":
                event.end = icsDate(line.value)?.date
            default: break
            }
        }
        if event.title.isEmpty { event.title = event.location ?? "Event" }
        return event.start == nil && event.location == nil && event.title == "Event" ? nil : event
    }

    /// Parses `20261003T140000Z` (UTC), `20261003T140000` (local) and `20261003` (all day).
    public static func icsDate(_ value: String) -> (date: Date, allDay: Bool)? {
        let text = value.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if text.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            if let date = formatter.date(from: text) { return (date, false) }
            formatter.dateFormat = "yyyyMMdd'T'HHmm'Z'"
            return formatter.date(from: text).map { ($0, false) }
        }
        formatter.timeZone = .current
        if text.count == 8 {
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: text).map { ($0, true) }
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let date = formatter.date(from: text) { return (date, false) }
        formatter.dateFormat = "yyyyMMdd'T'HHmm"
        return formatter.date(from: text).map { ($0, false) }
    }

    static func icsString(_ date: Date, allDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if allDay {
            formatter.timeZone = .current
            formatter.dateFormat = "yyyyMMdd"
        } else {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        }
        return formatter.string(from: date)
    }

    // MARK: Payment

    static func payment(_ text: String) -> KitoPaymentRequest? {
        guard let components = URLComponents(string: text) else { return nil }
        let query = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
                               uniquingKeysWith: { first, _ in first })
        let path = components.path.split(separator: "/").map(String.init)
        let kindText = (components.host ?? query["type"] ?? path.first ?? "").lowercased()
        guard let kind = KitoPaymentRequest.Kind(rawValue: kindText) else { return nil }
        let number = (query["number"] ?? path.last(where: { $0.lowercased() != kindText }) ?? "").filter { !$0.isWhitespace }
        guard !number.isEmpty, number.allSatisfy({ $0.isNumber || $0 == "+" }) else { return nil }
        let amount = query["amount"].flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let validAmount = amount.flatMap { $0 > 0 ? $0 : nil }
        return KitoPaymentRequest(kind: kind, number: number,
                                  account: query["account"].flatMap(nonEmpty),
                                  amount: validAmount,
                                  currency: (query["currency"].flatMap(nonEmpty) ?? "KES").uppercased(),
                                  merchant: query["name"].flatMap(nonEmpty),
                                  note: query["note"].flatMap(nonEmpty))
    }

    // MARK: Phone, email, SMS, geo, URL

    static func phone(_ text: String) -> String? {
        let value = (text.removingPercentEncoding ?? text).trimmingCharacters(in: .whitespaces)
        let allowed = value.allSatisfy { $0.isNumber || " +-().".contains($0) }
        let digits = value.filter(\.isNumber).count
        return allowed && (3...15).contains(digits) ? value : nil
    }

    static func mailto(_ text: String) -> KitoEmailMessage? {
        let rest = String(text.dropFirst(7))
        let parts = rest.split(separator: "?", maxSplits: 1).map(String.init)
        let address = (parts.first ?? "").removingPercentEncoding ?? ""
        guard !address.isEmpty else { return nil }
        let query = parts.count > 1 ? queryPairs(parts[1]) : [:]
        return KitoEmailMessage(address: address, subject: query["subject"].flatMap(nonEmpty), body: query["body"].flatMap(nonEmpty))
    }

    static func sms(_ text: String) -> KitoTextMessage? {
        if text.uppercased().hasPrefix("SMSTO:") {
            let parts = text.dropFirst(6).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let number = parts.first, !number.isEmpty else { return nil }
            return KitoTextMessage(number: number, body: parts.count > 1 ? nonEmpty(parts[1]) : nil)
        }
        let rest = String(text.dropFirst(4))
        let splitIndex = rest.firstIndex(where: { $0 == "?" || $0 == "&" })
        let number = String(splitIndex.map { rest[..<$0] } ?? Substring(rest)).trimmingCharacters(in: CharacterSet(charactersIn: ";, "))
        guard !number.isEmpty else { return nil }
        let query = splitIndex.map { queryPairs(String(rest[rest.index(after: $0)...])) } ?? [:]
        return KitoTextMessage(number: number.removingPercentEncoding ?? number, body: query["body"].flatMap(nonEmpty))
    }

    static func geo(_ text: String) -> KitoGeoPoint? {
        let rest = String(text.dropFirst(4))
        let parts = rest.split(separator: "?", maxSplits: 1).map(String.init)
        let coordinates = (parts.first ?? "").split(separator: ";").first.map(String.init) ?? ""
        let numbers = coordinates.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count >= 2, let latitude = numbers[0], let longitude = numbers[1],
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let altitude = numbers.count > 2 ? numbers[2] : nil
        let query = parts.count > 1 ? queryPairs(parts[1])["q"].flatMap(nonEmpty) : nil
        return KitoGeoPoint(latitude: latitude, longitude: longitude, altitude: altitude, query: query)
    }

    static func webURL(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
            return url
        }
        if lower.hasPrefix("www."), text.contains(".") {
            return URL(string: "https://" + text)
        }
        return nil
    }

    static func isEmailAddress(_ text: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `a=1&b=two%20words` → ["a": "1", "b": "two words"] (keys lowercased).
    static func queryPairs(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first?.lowercased(), !key.isEmpty, result[key] == nil else { continue }
            let value = parts.count > 1 ? parts[1] : ""
            result[key] = value.removingPercentEncoding ?? value
        }
        return result
    }

    static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
