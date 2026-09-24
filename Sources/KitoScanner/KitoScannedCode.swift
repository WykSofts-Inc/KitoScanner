//
//  KitoScannedCode.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// The barcode families the scanner can read. Pass a set to `KitoCodeScanner` to limit what it
/// looks for: fewer symbologies means faster, more reliable detection.
public enum KitoSymbology: String, CaseIterable, Hashable, Sendable {
    case qr, aztec, pdf417, dataMatrix
    case ean13, ean8, upce, code128, code39, code93, itf14, codabar

    /// Every 2D code: QR, Aztec, PDF417 and Data Matrix.
    public static let twoDimensional: Set<KitoSymbology> = [.qr, .aztec, .pdf417, .dataMatrix]
    /// Retail product barcodes: EAN-13 (which includes UPC-A), EAN-8 and UPC-E.
    public static let retail: Set<KitoSymbology> = [.ean13, .ean8, .upce]
    /// Every symbology.
    public static let all = Set(KitoSymbology.allCases)

    /// A short human name, e.g. "QR" or "EAN-13".
    public var title: String {
        switch self {
        case .qr: return "QR"
        case .aztec: return "Aztec"
        case .pdf417: return "PDF417"
        case .dataMatrix: return "Data Matrix"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .itf14: return "ITF-14"
        case .codabar: return "Codabar"
        }
    }

    /// True for 2D codes (QR, Aztec, PDF417, Data Matrix).
    public var isTwoDimensional: Bool { Self.twoDimensional.contains(self) }
}

/// One code the scanner read: the raw string, what kind of barcode carried it, when, and what
/// it means once parsed.
public struct KitoScannedCode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let raw: String
    public let symbology: KitoSymbology?
    public let date: Date
    public let payload: KitoCodePayload

    /// Parses `raw` into a payload.
    public init(raw: String, symbology: KitoSymbology? = nil, date: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.raw = raw
        self.symbology = symbology
        self.date = date
        self.payload = KitoCodeParser.parse(raw, symbology: symbology)
    }
}

/// What a scanned code contains.
public enum KitoCodePayload: Hashable, Sendable {
    case url(URL)
    case wifi(KitoWiFiNetwork)
    case contact(KitoContactCard)
    case phone(String)
    case email(KitoEmailMessage)
    case sms(KitoTextMessage)
    case geo(KitoGeoPoint)
    case event(KitoCalendarEvent)
    case payment(KitoPaymentRequest)
    case product(KitoProductCode)
    case text(String)

    /// The kind of payload, without its values.
    public var kind: KitoPayloadKind {
        switch self {
        case .url: return .url
        case .wifi: return .wifi
        case .contact: return .contact
        case .phone: return .phone
        case .email: return .email
        case .sms: return .sms
        case .geo: return .geo
        case .event: return .event
        case .payment: return .payment
        case .product: return .product
        case .text: return .text
        }
    }

    /// A one-line summary suitable for a list row, e.g. the network name or the link host.
    public var summary: String {
        switch self {
        case .url(let url): return url.host ?? url.absoluteString
        case .wifi(let network): return network.ssid
        case .contact(let card): return card.name
        case .phone(let number): return number
        case .email(let message): return message.address
        case .sms(let message): return message.number
        case .geo(let point): return point.query ?? point.coordinateText
        case .event(let event): return event.title
        case .payment(let request): return request.merchant ?? request.number
        case .product(let code): return code.digits
        case .text(let text): return text
        }
    }
}

/// The kinds of payload, for icons, titles and filtering.
public enum KitoPayloadKind: String, CaseIterable, Hashable, Sendable {
    case url, wifi, contact, phone, email, sms, geo, event, payment, product, text

    public var title: String {
        switch self {
        case .url: return "Link"
        case .wifi: return "Wi-Fi network"
        case .contact: return "Contact"
        case .phone: return "Phone number"
        case .email: return "Email"
        case .sms: return "Text message"
        case .geo: return "Location"
        case .event: return "Event"
        case .payment: return "Payment"
        case .product: return "Product"
        case .text: return "Text"
        }
    }

    /// An SF Symbol for the kind.
    public var systemImage: String {
        switch self {
        case .url: return "link"
        case .wifi: return "wifi"
        case .contact: return "person.crop.circle.fill"
        case .phone: return "phone.fill"
        case .email: return "envelope.fill"
        case .sms: return "message.fill"
        case .geo: return "mappin.and.ellipse"
        case .event: return "calendar"
        case .payment: return "creditcard.fill"
        case .product: return "barcode"
        case .text: return "text.alignleft"
        }
    }
}

// MARK: - Payload types

/// A Wi-Fi network from a `WIFI:S:…;T:…;P:…;;` code.
public struct KitoWiFiNetwork: Hashable, Sendable {
    public enum Security: String, Hashable, Sendable {
        /// WPA, WPA2 or WPA3 personal.
        case wpa
        case wep
        case open

        public var title: String {
            switch self {
            case .wpa: return "WPA/WPA2"
            case .wep: return "WEP"
            case .open: return "Open"
            }
        }
    }

    public var ssid: String
    public var password: String?
    public var security: Security
    public var isHidden: Bool

    public init(ssid: String, password: String? = nil, security: Security = .wpa, isHidden: Bool = false) {
        self.ssid = ssid
        self.password = password
        self.security = password == nil ? .open : security
        self.isHidden = isHidden
    }

    /// The `WIFI:` string to put in a QR code, with `\ ; , : "` escaped.
    public var payload: String {
        var parts = ["S:\(KitoCodeParser.escape(ssid))"]
        switch security {
        case .wpa: parts.append("T:WPA")
        case .wep: parts.append("T:WEP")
        case .open: parts.append("T:nopass")
        }
        if let password, security != .open { parts.append("P:\(KitoCodeParser.escape(password))") }
        if isHidden { parts.append("H:true") }
        return "WIFI:" + parts.joined(separator: ";") + ";;"
    }
}

/// A contact from a vCard or MECARD code.
public struct KitoContactCard: Hashable, Sendable {
    public var name: String
    public var organization: String?
    public var jobTitle: String?
    public var phones: [String]
    public var emails: [String]
    public var address: String?
    public var website: String?
    public var note: String?

    public init(name: String, organization: String? = nil, jobTitle: String? = nil, phones: [String] = [], emails: [String] = [],
                address: String? = nil, website: String? = nil, note: String? = nil) {
        self.name = name
        self.organization = organization
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.address = address
        self.website = website
        self.note = note
    }

    /// A vCard 3.0 string to put in a QR code.
    public var vCard: String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0", "FN:\(KitoCodeParser.escapeICS(name))"]
        let pieces = name.split(separator: " ").map(String.init)
        if let last = pieces.last, pieces.count > 1 {
            lines.append("N:\(last);\(pieces.dropLast().joined(separator: " "));;;")
        } else {
            lines.append("N:\(name);;;;")
        }
        if let organization { lines.append("ORG:\(KitoCodeParser.escapeICS(organization))") }
        if let jobTitle { lines.append("TITLE:\(KitoCodeParser.escapeICS(jobTitle))") }
        lines += phones.map { "TEL;TYPE=CELL:\($0)" }
        lines += emails.map { "EMAIL:\($0)" }
        if let address { lines.append("ADR:;;\(KitoCodeParser.escapeICS(address));;;;") }
        if let website { lines.append("URL:\(website)") }
        if let note { lines.append("NOTE:\(KitoCodeParser.escapeICS(note))") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\n")
    }
}

/// An email from a `mailto:` or `MATMSG:` code.
public struct KitoEmailMessage: Hashable, Sendable {
    public var address: String
    public var subject: String?
    public var body: String?

    public init(address: String, subject: String? = nil, body: String? = nil) {
        self.address = address
        self.subject = subject
        self.body = body
    }

    /// A `mailto:` URL, if the address makes one.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        var items: [URLQueryItem] = []
        if let subject { items.append(URLQueryItem(name: "subject", value: subject)) }
        if let body { items.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}

/// A text message from an `sms:` or `SMSTO:` code.
public struct KitoTextMessage: Hashable, Sendable {
    public var number: String
    public var body: String?

    public init(number: String, body: String? = nil) {
        self.number = number
        self.body = body
    }

    /// An `sms:` URL that opens Messages with the body filled in.
    public var url: URL? {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        guard let body, let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return URL(string: "sms:\(digits)")
        }
        return URL(string: "sms:\(digits)&body=\(encoded)")
    }

    /// The `SMSTO:` string to put in a QR code.
    public var payload: String { "SMSTO:\(number):\(body ?? "")" }
}

/// A point on the map from a `geo:` code.
public struct KitoGeoPoint: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var query: String?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil, query: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.query = query
    }

    /// "-1.28638, 36.81723"
    public var coordinateText: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    /// An Apple Maps URL that drops a pin here.
    public var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")]
        items.append(URLQueryItem(name: "q", value: query ?? coordinateText))
        components?.queryItems = items
        return components?.url
    }

    /// The `geo:` string to put in a QR code.
    public var payload: String {
        var text = "geo:\(latitude),\(longitude)"
        if let altitude { text += ",\(altitude)" }
        if let query, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { text += "?q=\(encoded)" }
        return text
    }
}

/// An event from a `BEGIN:VEVENT` code.
public struct KitoCalendarEvent: Hashable, Sendable {
    public var title: String
    public var start: Date?
    public var end: Date?
    public var location: String?
    public var notes: String?
    public var isAllDay: Bool

    public init(title: String, start: Date? = nil, end: Date? = nil, location: String? = nil, notes: String? = nil, isAllDay: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
    }

    /// A `BEGIN:VEVENT` string (times in UTC) to put in a QR code.
    public var payload: String {
        var lines = ["BEGIN:VEVENT", "SUMMARY:\(KitoCodeParser.escapeICS(title))"]
        if let start { lines.append("DTSTART:\(KitoCodeParser.icsString(start, allDay: isAllDay))") }
        if let end { lines.append("DTEND:\(KitoCodeParser.icsString(end, allDay: isAllDay))") }
        if let location { lines.append("LOCATION:\(KitoCodeParser.escapeICS(location))") }
        if let notes { lines.append("DESCRIPTION:\(KitoCodeParser.escapeICS(notes))") }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\n")
    }
}

/// A mobile-money payment request, M-Pesa style, from a `kitopay://` code:
///
///     kitopay://till/832910?amount=450&name=Mama%20Mboga%20Greens
///     kitopay://paybill/247247?account=0712345678&amount=2500&name=Nairobi%20Water
///     kitopay://phone/254712345678?amount=1000&name=Achieng
///
/// The scheme is Kito's own, a stand-in for whatever your payment provider uses.
public struct KitoPaymentRequest: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        /// Buy Goods till number.
        case till
        /// Paybill business number, with an account number.
        case paybill
        /// Send money to a phone number.
        case phone

        public var title: String {
            switch self {
            case .till: return "Till number"
            case .paybill: return "Paybill"
            case .phone: return "Phone"
            }
        }
    }

    public var kind: Kind
    public var number: String
    public var account: String?
    public var amount: Decimal?
    public var currency: String
    public var merchant: String?
    public var note: String?

    public init(kind: Kind, number: String, account: String? = nil, amount: Decimal? = nil, currency: String = "KES",
                merchant: String? = nil, note: String? = nil) {
        self.kind = kind
        self.number = number
        self.account = account
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.note = note
    }

    /// "KES 1,500" or nil when there's no amount.
    public var formattedAmount: String? {
        guard let amount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_KE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "\(currency) \(number)"
    }

    /// The `kitopay://` string to put in a QR code.
    public var payload: String {
        var components = URLComponents()
        components.scheme = KitoCodeParser.paymentScheme
        components.host = kind.rawValue
        components.path = "/" + number
        var items: [URLQueryItem] = []
        if let account { items.append(URLQueryItem(name: "account", value: account)) }
        if let amount { items.append(URLQueryItem(name: "amount", value: "\(amount)")) }
        if currency != "KES" { items.append(URLQueryItem(name: "currency", value: currency)) }
        if let merchant { items.append(URLQueryItem(name: "name", value: merchant)) }
        if let note { items.append(URLQueryItem(name: "note", value: note)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "\(KitoCodeParser.paymentScheme)://\(kind.rawValue)/\(number)"
    }
}

/// A retail product number (GTIN) with its check digit verified.
public struct KitoProductCode: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case ean13, ean8, upcA, upcE, gtin14

        public var title: String {
            switch self {
            case .ean13: return "EAN-13"
            case .ean8: return "EAN-8"
            case .upcA: return "UPC-A"
            case .upcE: return "UPC-E"
            case .gtin14: return "GTIN-14"
            }
        }
    }

    public var digits: String
    public var kind: Kind
    /// Whether the last digit matches the check digit computed from the others.
    public var isValid: Bool

    public init(digits: String, kind: Kind) {
        self.digits = digits
        self.kind = kind
        self.isValid = kind == .upcE ? KitoCheckDigits.isValidUPCE(digits) : KitoCheckDigits.isValidGTIN(digits)
    }

    /// The GS1 country or region for EAN-13 prefixes this knows, e.g. "Kenya" for 616.
    public var region: String? {
        guard kind == .ean13 || kind == .upcA else { return nil }
        let normalized = kind == .upcA ? "0" + digits : digits
        return KitoCheckDigits.gs1Region(forEAN13: normalized)
    }
}
