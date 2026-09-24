//
//  KitoCodeParserTests.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoScanner

final class KitoCodeParserTests: XCTestCase {
    private func parse(_ raw: String, _ symbology: KitoSymbology? = nil) -> KitoCodePayload {
        KitoCodeParser.parse(raw, symbology: symbology)
    }

    // MARK: URL

    func testHTTPSURL() {
        guard case .url(let url) = parse("https://kito.dev/pay?ref=42") else { return XCTFail("not a url") }
        XCTAssertEqual(url.host, "kito.dev")
    }

    func testWWWGetsHTTPS() {
        guard case .url(let url) = parse("www.example.co.ke") else { return XCTFail("not a url") }
        XCTAssertEqual(url.absoluteString, "https://www.example.co.ke")
    }

    func testTextWithSpacesIsNotURL() {
        XCTAssertEqual(parse("https://kito.dev is great").kind, .text)
    }

    // MARK: Wi-Fi

    func testWiFiWPA() {
        guard case .wifi(let network) = parse("WIFI:S:Kahawa House Guest;T:WPA;P:karibu2026;;") else { return XCTFail("not wifi") }
        XCTAssertEqual(network.ssid, "Kahawa House Guest")
        XCTAssertEqual(network.password, "karibu2026")
        XCTAssertEqual(network.security, .wpa)
        XCTAssertFalse(network.isHidden)
    }

    func testWiFiFieldsInAnyOrderWithEscapes() {
        guard case .wifi(let network) = parse(#"WIFI:T:WEP;P:pa\;ss\:word;S:Cafe\,Nairobi;H:true;;"#) else { return XCTFail("not wifi") }
        XCTAssertEqual(network.ssid, "Cafe,Nairobi")
        XCTAssertEqual(network.password, "pa;ss:word")
        XCTAssertEqual(network.security, .wep)
        XCTAssertTrue(network.isHidden)
    }

    func testWiFiOpenNetwork() {
        guard case .wifi(let network) = parse("WIFI:S:Airport Free;T:nopass;;") else { return XCTFail("not wifi") }
        XCTAssertEqual(network.security, .open)
        XCTAssertNil(network.password)
    }

    func testWiFiPayloadRoundTrip() {
        let network = KitoWiFiNetwork(ssid: "Mama;Mboga", password: #"p@ss\word"#, security: .wpa, isHidden: true)
        guard case .wifi(let parsed) = parse(network.payload) else { return XCTFail("not wifi") }
        XCTAssertEqual(parsed, network)
    }

    func testWiFiWithoutSSIDIsText() {
        XCTAssertEqual(parse("WIFI:T:WPA;P:secret;;").kind, .text)
    }

    // MARK: Contacts

    func testMECARD() {
        let raw = "MECARD:N:Owuor,Achieng;TEL:+254712345678;TEL:+254733000111;EMAIL:achieng@example.co.ke;ORG:Safari Tech;ADR:Kenyatta Ave, Nairobi;;"
        guard case .contact(let card) = parse(raw) else { return XCTFail("not a contact") }
        XCTAssertEqual(card.name, "Achieng Owuor")
        XCTAssertEqual(card.phones, ["+254712345678", "+254733000111"])
        XCTAssertEqual(card.emails, ["achieng@example.co.ke"])
        XCTAssertEqual(card.organization, "Safari Tech")
    }

    func testVCardWithFoldingAndParams() {
        let raw = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Kamau;Wanjiru;;Dr.;\r\nORG:Parklands Heart Clinic;Cardiology\r\nTITLE:Consultant\r\nTEL;TYPE=CELL:+254 722 000 111\r\nEMAIL;TYPE=WORK:wanjiru@example.org\r\nADR;TYPE=WORK:;;3rd Parklands Ave;Nairobi;;00100;Kenya\r\nNOTE:Clinic hours Mon\\, Wed\r\n  and Fri\r\nEND:VCARD"
        guard case .contact(let card) = parse(raw) else { return XCTFail("not a contact") }
        XCTAssertEqual(card.name, "Dr. Wanjiru Kamau")
        XCTAssertEqual(card.organization, "Parklands Heart Clinic")
        XCTAssertEqual(card.jobTitle, "Consultant")
        XCTAssertEqual(card.phones, ["+254 722 000 111"])
        XCTAssertEqual(card.address, "3rd Parklands Ave, Nairobi, 00100, Kenya")
        XCTAssertEqual(card.note, "Clinic hours Mon, Wed and Fri")
    }

    func testVCardFNWins() {
        let raw = "BEGIN:VCARD\nVERSION:3.0\nFN:Baraka Mwangi\nN:Mwangi;Baraka;;;\nEND:VCARD"
        guard case .contact(let card) = parse(raw) else { return XCTFail("not a contact") }
        XCTAssertEqual(card.name, "Baraka Mwangi")
    }

    func testVCardRoundTrip() {
        let card = KitoContactCard(name: "Zawadi Njeri", organization: "Kito", phones: ["+255754000222"], emails: ["zawadi@kito.dev"])
        guard case .contact(let parsed) = parse(card.vCard) else { return XCTFail("not a contact") }
        XCTAssertEqual(parsed.name, "Zawadi Njeri")
        XCTAssertEqual(parsed.phones, card.phones)
        XCTAssertEqual(parsed.emails, card.emails)
        XCTAssertEqual(parsed.organization, "Kito")
    }

    // MARK: Phone, email, SMS

    func testTel() {
        XCTAssertEqual(parse("tel:+254712345678"), .phone("+254712345678"))
    }

    func testBarePlusNumberIsPhone() {
        XCTAssertEqual(parse("+256 772 123456"), .phone("+256 772 123456"))
    }

    func testMailto() {
        guard case .email(let message) = parse("mailto:hello@kito.dev?subject=Order%2042&body=Asante") else { return XCTFail("not email") }
        XCTAssertEqual(message.address, "hello@kito.dev")
        XCTAssertEqual(message.subject, "Order 42")
        XCTAssertEqual(message.body, "Asante")
    }

    func testMATMSG() {
        guard case .email(let message) = parse("MATMSG:TO:support@kito.dev;SUB:Help;BODY:My order;;") else { return XCTFail("not email") }
        XCTAssertEqual(message.address, "support@kito.dev")
        XCTAssertEqual(message.subject, "Help")
    }

    func testBareEmail() {
        XCTAssertEqual(parse("achieng@example.co.ke"), .email(KitoEmailMessage(address: "achieng@example.co.ke")))
    }

    func testSMSTO() {
        XCTAssertEqual(parse("SMSTO:+254712345678:Nimefika"), .sms(KitoTextMessage(number: "+254712345678", body: "Nimefika")))
    }

    func testSMSURL() {
        XCTAssertEqual(parse("sms:+254712345678?body=Habari%20yako"), .sms(KitoTextMessage(number: "+254712345678", body: "Habari yako")))
    }

    // MARK: Geo

    func testGeo() {
        guard case .geo(let point) = parse("geo:-1.28638,36.81723?q=Kenyatta%20Avenue") else { return XCTFail("not geo") }
        XCTAssertEqual(point.latitude, -1.28638, accuracy: 0.00001)
        XCTAssertEqual(point.longitude, 36.81723, accuracy: 0.00001)
        XCTAssertEqual(point.query, "Kenyatta Avenue")
    }

    func testGeoWithAltitude() {
        guard case .geo(let point) = parse("geo:-3.0674,37.3556,5895") else { return XCTFail("not geo") }
        XCTAssertEqual(point.altitude, 5895)
    }

    func testGeoOutOfRangeIsText() {
        XCTAssertEqual(parse("geo:120,36").kind, .text)
    }

    func testGeoRoundTrip() {
        let point = KitoGeoPoint(latitude: -4.0435, longitude: 39.6682, query: "Fort Jesus")
        XCTAssertEqual(parse(point.payload), .geo(point))
    }

    // MARK: Events

    func testEventUTC() {
        let raw = "BEGIN:VEVENT\nSUMMARY:Nairobi Tech Week\nDTSTART:20261003T060000Z\nDTEND:20261003T140000Z\nLOCATION:KICC\\, Nairobi\nEND:VEVENT"
        guard case .event(let event) = parse(raw) else { return XCTFail("not an event") }
        XCTAssertEqual(event.title, "Nairobi Tech Week")
        XCTAssertEqual(event.location, "KICC, Nairobi")
        XCTAssertEqual(event.start?.timeIntervalSince1970, 1_791_007_200)
        XCTAssertEqual(event.end.map { $0.timeIntervalSince(event.start ?? $0) }, 8 * 3_600)
        XCTAssertFalse(event.isAllDay)
    }

    func testEventInsideVCalendarAllDay() {
        let raw = "BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nSUMMARY:Madaraka Day\nDTSTART;VALUE=DATE:20270601\nEND:VEVENT\nEND:VCALENDAR"
        guard case .event(let event) = parse(raw) else { return XCTFail("not an event") }
        XCTAssertEqual(event.title, "Madaraka Day")
        XCTAssertTrue(event.isAllDay)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: event.start ?? Date())
        XCTAssertEqual([parts.year, parts.month, parts.day], [2027, 6, 1])
    }

    func testEventRoundTrip() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = KitoCalendarEvent(title: "Safari Rally, Naivasha", start: start, end: start.addingTimeInterval(7_200), location: "Kasarani")
        guard case .event(let parsed) = parse(event.payload) else { return XCTFail("not an event") }
        XCTAssertEqual(parsed, event)
    }

    // MARK: Payments

    func testTillPayment() {
        guard case .payment(let request) = parse("kitopay://till/832910?amount=450&name=Mama%20Mboga%20Greens") else { return XCTFail("not a payment") }
        XCTAssertEqual(request.kind, .till)
        XCTAssertEqual(request.number, "832910")
        XCTAssertEqual(request.amount, Decimal(450))
        XCTAssertEqual(request.currency, "KES")
        XCTAssertEqual(request.merchant, "Mama Mboga Greens")
        XCTAssertEqual(request.formattedAmount, "KES 450")
    }

    func testPaybillWithAccount() {
        guard case .payment(let request) = parse("kitopay://paybill/247247?account=0712345678&amount=2500.50&currency=kes") else { return XCTFail("not a payment") }
        XCTAssertEqual(request.kind, .paybill)
        XCTAssertEqual(request.account, "0712345678")
        XCTAssertEqual(request.amount, Decimal(string: "2500.50"))
        XCTAssertEqual(request.formattedAmount, "KES 2,500.5")
    }

    func testPaymentQueryStyle() {
        guard case .payment(let request) = parse("kitopay:pay?type=phone&number=255754000222&currency=TZS&amount=15000") else { return XCTFail("not a payment") }
        XCTAssertEqual(request.kind, .phone)
        XCTAssertEqual(request.number, "255754000222")
        XCTAssertEqual(request.currency, "TZS")
    }

    func testPaymentRejectsBadKindAndNumber() {
        XCTAssertEqual(parse("kitopay://bank/123").kind, .text)
        XCTAssertEqual(parse("kitopay://till/12ab").kind, .text)
    }

    func testNegativeAmountIsDropped() {
        guard case .payment(let request) = parse("kitopay://till/832910?amount=-20") else { return XCTFail("not a payment") }
        XCTAssertNil(request.amount)
    }

    func testPaymentRoundTrip() {
        let request = KitoPaymentRequest(kind: .paybill, number: "888880", account: "INV-2026-004", amount: 12_500, merchant: "Mwangaza Power")
        XCTAssertEqual(parse(request.payload), .payment(request))
    }

    // MARK: Products

    func testEAN13Kenya() {
        guard case .product(let code) = parse("6161001234567", .ean13) else { return XCTFail("not a product") }
        XCTAssertEqual(code.kind, .ean13)
        XCTAssertTrue(code.isValid)
        XCTAssertEqual(code.region, "Kenya")
    }

    func testEAN13BadCheckDigit() {
        guard case .product(let code) = parse("6161001234568") else { return XCTFail("not a product") }
        XCTAssertFalse(code.isValid)
    }

    func testUPCA() {
        guard case .product(let code) = parse("036000291452") else { return XCTFail("not a product") }
        XCTAssertEqual(code.kind, .upcA)
        XCTAssertTrue(code.isValid)
    }

    func testEAN8AndUPCE() {
        guard case .product(let ean8) = parse("96385074", .ean8) else { return XCTFail("not a product") }
        XCTAssertEqual(ean8.kind, .ean8)
        XCTAssertTrue(ean8.isValid)
        guard case .product(let upce) = parse("04252614", .upce) else { return XCTFail("not a product") }
        XCTAssertEqual(upce.kind, .upcE)
        XCTAssertTrue(upce.isValid)
    }

    func testDigitsFromCode128AreText() {
        XCTAssertEqual(parse("6161001234567", .code128).kind, .text)
    }

    func testPlainText() {
        XCTAssertEqual(parse("  Karibu sana!  "), .text("Karibu sana!"))
    }

    func testScannedCodeKeepsRawAndSymbology() {
        let code = KitoScannedCode(raw: "https://kito.dev", symbology: .qr)
        XCTAssertEqual(code.raw, "https://kito.dev")
        XCTAssertEqual(code.symbology, .qr)
        XCTAssertEqual(code.payload.kind, .url)
        XCTAssertEqual(code.payload.summary, "kito.dev")
    }
}
