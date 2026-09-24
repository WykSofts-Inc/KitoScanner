//
//  KitoScannerMathTests.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoScanner

final class KitoCheckDigitTests: XCTestCase {
    func testGTINCheckDigits() {
        XCTAssertEqual(KitoCheckDigits.gtinCheckDigit(for: "616100123456"), 7)
        XCTAssertEqual(KitoCheckDigits.gtinCheckDigit(for: "400638133393"), 1)
        XCTAssertEqual(KitoCheckDigits.gtinCheckDigit(for: "9638507"), 4)
        XCTAssertNil(KitoCheckDigits.gtinCheckDigit(for: "12a4"))
        XCTAssertNil(KitoCheckDigits.gtinCheckDigit(for: ""))
    }

    func testGTINValidation() {
        XCTAssertTrue(KitoCheckDigits.isValidGTIN("5901234123457"))
        XCTAssertTrue(KitoCheckDigits.isValidGTIN("036000291452"))
        XCTAssertTrue(KitoCheckDigits.isValidGTIN("96385074"))
        XCTAssertTrue(KitoCheckDigits.isValidGTIN("6201005551236"))
        XCTAssertFalse(KitoCheckDigits.isValidGTIN("5901234123458"))
        XCTAssertFalse(KitoCheckDigits.isValidGTIN("590123412345"))
        XCTAssertFalse(KitoCheckDigits.isValidGTIN("123"))
    }

    func testAppendingCheckDigit() {
        XCTAssertEqual(KitoCheckDigits.appendingGTINCheckDigit(to: "616100123456"), "6161001234567")
    }

    func testUPCEExpansion() {
        XCTAssertEqual(KitoCheckDigits.expandUPCE("04252614"), "042100005264")
        XCTAssertEqual(KitoCheckDigits.expandUPCE("01234565"), "012345000065")
        XCTAssertTrue(KitoCheckDigits.isValidUPCE("04252614"))
        XCTAssertFalse(KitoCheckDigits.isValidUPCE("04252615"))
        XCTAssertNil(KitoCheckDigits.expandUPCE("24252614"))
    }

    func testLuhn() {
        XCTAssertTrue(KitoCheckDigits.isValidLuhn("4242 4242 4242 4242"))
        XCTAssertTrue(KitoCheckDigits.isValidLuhn("5555-5555-5555-4444"))
        XCTAssertTrue(KitoCheckDigits.isValidLuhn("378282246310005"))
        XCTAssertFalse(KitoCheckDigits.isValidLuhn("4242424242424241"))
        XCTAssertFalse(KitoCheckDigits.isValidLuhn("4242x42424242424"))
        XCTAssertEqual(KitoCheckDigits.luhnCheckDigit(for: "424242424242424"), 2)
    }
}

final class KitoCardTests: XCTestCase {
    func testBrands() {
        XCTAssertEqual(KitoCardBrand.detect("4242424242424242"), .visa)
        XCTAssertEqual(KitoCardBrand.detect("5555555555554444"), .mastercard)
        XCTAssertEqual(KitoCardBrand.detect("2223003122003222"), .mastercard)
        XCTAssertEqual(KitoCardBrand.detect("378282246310005"), .amex)
        XCTAssertEqual(KitoCardBrand.detect("6011111111111117"), .discover)
        XCTAssertEqual(KitoCardBrand.detect("3530111333300000"), .jcb)
        XCTAssertEqual(KitoCardBrand.detect("6200000000000005"), .unionPay)
        XCTAssertEqual(KitoCardBrand.detect("36227206271667"), .diners)
        XCTAssertEqual(KitoCardBrand.detect("9999"), .unknown)
    }

    func testMasking() {
        XCTAssertEqual(KitoCardMask.mask("4242424242424242"), "•••• •••• •••• 4242")
        XCTAssertEqual(KitoCardMask.mask("378282246310005"), "•••• •••••• •0005")
        XCTAssertEqual(KitoCardMask.mask("4242 4242 4242 4242 123"), "•••• •••• •••• •••2 123")
        XCTAssertEqual(KitoCardMask.mask("4242424242424242", visible: 0), "•••• •••• •••• ••••")
        XCTAssertEqual(KitoCardMask.mask(""), "")
    }

    func testDetailsNeverKeepFullNumber() {
        let details = KitoCardDetails(number: "4242 4242 4242 4242", expiry: KitoCardExpiry(month: 8, year: 2029), holderName: "Achieng Owuor")
        XCTAssertEqual(details.last4, "4242")
        XCTAssertEqual(details.brand, .visa)
        XCTAssertTrue(details.isNumberValid)
        let mirror = Mirror(reflecting: details)
        for child in mirror.children {
            XCTAssertFalse(String(describing: child.value).contains("424242424242"), "\(child.label ?? "") leaks the number")
        }
    }

    func testExpiryParsing() {
        XCTAssertEqual(KitoCardExpiry.parse("VALID THRU 08/29"), KitoCardExpiry(month: 8, year: 2029))
        XCTAssertEqual(KitoCardExpiry.parse("EXP 12/2030"), KitoCardExpiry(month: 12, year: 2030))
        XCTAssertEqual(KitoCardExpiry.parse("GOOD THRU 03 - 27"), KitoCardExpiry(month: 3, year: 2027))
        XCTAssertEqual(KitoCardExpiry.parse("VALID FROM 01/24 THRU 01/28"), KitoCardExpiry(month: 1, year: 2028))
        XCTAssertNil(KitoCardExpiry.parse("13/29"))
        XCTAssertNil(KitoCardExpiry.parse("4242424242424242"))
        XCTAssertEqual(KitoCardExpiry(month: 8, year: 2029)?.formatted, "08/29")
    }

    func testExpiryIsExpired() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24)) ?? Date()
        XCTAssertFalse(KitoCardExpiry(month: 9, year: 2026)?.isExpired(on: date, calendar: calendar) ?? true)
        XCTAssertTrue(KitoCardExpiry(month: 8, year: 2026)?.isExpired(on: date, calendar: calendar) ?? false)
        XCTAssertFalse(KitoCardExpiry(month: 1, year: 2027)?.isExpired(on: date, calendar: calendar) ?? true)
    }

    func testCardTextParsing() {
        let lines = ["KITO BANK", "DEBIT", "4242 4242 4242 4242", "VALID", "THRU 08/29", "ACHIENG W OWUOR", "VISA"]
        let details = KitoCardTextParser.details(from: lines)
        XCTAssertEqual(details?.last4, "4242")
        XCTAssertEqual(details?.maskedNumber, "•••• •••• •••• 4242")
        XCTAssertEqual(details?.expiry, KitoCardExpiry(month: 8, year: 2029))
        XCTAssertEqual(details?.holderName, "Achieng W Owuor")
    }

    func testCardTextFixesOCRSlipsAndSplitLines() {
        XCTAssertEqual(KitoCardTextParser.details(from: ["5555 5555 5555 4444"])?.brand, .mastercard)
        XCTAssertEqual(KitoCardTextParser.details(from: ["4OOO O566 5566 5556"])?.last4, "5556")
        XCTAssertEqual(KitoCardTextParser.details(from: ["5555 5555 SSSS 4444"])?.last4, "4444")
        XCTAssertEqual(KitoCardTextParser.details(from: ["4242 4242", "4242 4242"])?.last4, "4242")
    }

    func testCardTextRejectsInvalidNumbers() {
        XCTAssertNil(KitoCardTextParser.details(from: ["4242 4242 4242 4241", "JOHN KAMAU"]))
        XCTAssertNil(KitoCardTextParser.details(from: ["Call 0712 345 678"]))
    }

    func testNameHeuristics() {
        XCTAssertTrue(KitoCardTextParser.isNameLike("BARAKA MWANGI"))
        XCTAssertFalse(KitoCardTextParser.isNameLike("VALID THRU"))
        XCTAssertFalse(KitoCardTextParser.isNameLike("PLATINUM DEBIT"))
        XCTAssertFalse(KitoCardTextParser.isNameLike("Baraka"))
        XCTAssertFalse(KitoCardTextParser.isNameLike("08/29 BARAKA"))
    }
}

final class KitoGeometryTests: XCTestCase {
    func testSquareCutoutIsCentredAndCapped() {
        let rect = KitoScanGeometry.cutout(in: CGSize(width: 390, height: 844))
        XCTAssertEqual(rect.width, 273, accuracy: 0.01)
        XCTAssertEqual(rect.height, rect.width, accuracy: 0.01)
        XCTAssertEqual(rect.midX, 195, accuracy: 0.01)
        XCTAssertLessThan(rect.midY, 422)
        let wide = KitoScanGeometry.cutout(in: CGSize(width: 1_000, height: 800))
        XCTAssertEqual(wide.width, 300, accuracy: 0.01)
    }

    func testWideCutoutAndHeightLimit() {
        let barcode = KitoScanGeometry.cutout(in: CGSize(width: 400, height: 800), aspectRatio: 2)
        XCTAssertEqual(barcode.width / barcode.height, 2, accuracy: 0.001)
        let short = KitoScanGeometry.cutout(in: CGSize(width: 400, height: 200), aspectRatio: 1)
        XCTAssertEqual(short.height, 160, accuracy: 0.01)
        XCTAssertEqual(short.width, 160, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(short.minY, 0)
        XCTAssertEqual(KitoScanGeometry.cutout(in: .zero), .zero)
    }

    func testBracketLength() {
        XCTAssertEqual(KitoScanGeometry.bracketLength(for: CGRect(x: 0, y: 0, width: 200, height: 200)), 36, accuracy: 0.01)
        XCTAssertEqual(KitoScanGeometry.bracketLength(for: CGRect(x: 0, y: 0, width: 60, height: 60)), 18)
        XCTAssertEqual(KitoScanGeometry.bracketLength(for: CGRect(x: 0, y: 0, width: 600, height: 600)), 44)
    }

    func testLaserPingPongs() {
        XCTAssertEqual(KitoScanGeometry.laserOffset(progress: 0, height: 216, inset: 8), 8, accuracy: 0.01)
        XCTAssertEqual(KitoScanGeometry.laserOffset(progress: 0.5, height: 216, inset: 8), 108, accuracy: 0.01)
        XCTAssertEqual(KitoScanGeometry.laserOffset(progress: 1, height: 216, inset: 8), 208, accuracy: 0.01)
        XCTAssertEqual(KitoScanGeometry.laserOffset(progress: 1.5, height: 216, inset: 8), 108, accuracy: 0.01)
        XCTAssertEqual(KitoScanGeometry.laserOffset(progress: 2.25, height: 216, inset: 8), 58, accuracy: 0.01)
    }

    func testAspectFitAndFill() {
        let fit = KitoScanGeometry.aspectFitRect(content: CGSize(width: 400, height: 200), in: CGSize(width: 200, height: 200))
        XCTAssertEqual(fit, CGRect(x: 0, y: 50, width: 200, height: 100))
        let fill = KitoScanGeometry.aspectFillRect(content: CGSize(width: 400, height: 200), in: CGSize(width: 200, height: 200))
        XCTAssertEqual(fill, CGRect(x: -100, y: 0, width: 400, height: 200))
    }

    func testVisionBoxFlipsY() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let rect = KitoScanGeometry.viewRect(forVisionBox: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.3), imageFrame: frame)
        XCTAssertEqual(rect.minX, 60, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 80, accuracy: 0.001)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 30, accuracy: 0.001)
    }

    func testInsideWindowAndHighlight() {
        let window = CGRect(x: 100, y: 100, width: 200, height: 200)
        XCTAssertTrue(KitoScanGeometry.isInside(CGRect(x: 150, y: 150, width: 40, height: 40), window: window))
        XCTAssertTrue(KitoScanGeometry.isInside(CGRect(x: 290, y: 150, width: 40, height: 40), window: window))
        XCTAssertFalse(KitoScanGeometry.isInside(CGRect(x: 10, y: 10, width: 20, height: 20), window: window))
        let highlight = KitoScanGeometry.highlightRect(around: CGRect(x: 100, y: 100, width: 10, height: 80))
        XCTAssertEqual(highlight.width, 44, accuracy: 0.001)
        XCTAssertEqual(highlight.height, 96, accuracy: 0.001)
        XCTAssertEqual(highlight.midX, 105, accuracy: 0.001)
    }
}

final class KitoScanStateTests: XCTestCase {
    func testThrottleIgnoresRepeatsUntilCooldown() {
        var throttle = KitoScanThrottle(cooldown: 2)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(throttle.shouldAccept("a", at: start))
        XCTAssertFalse(throttle.shouldAccept("a", at: start.addingTimeInterval(1)))
        XCTAssertTrue(throttle.shouldAccept("b", at: start.addingTimeInterval(1.1)))
        XCTAssertFalse(throttle.shouldAccept("a", at: start.addingTimeInterval(2.5)))
        XCTAssertTrue(throttle.shouldAccept("a", at: start.addingTimeInterval(5)))
        throttle.reset()
        XCTAssertTrue(throttle.shouldAccept("a", at: start.addingTimeInterval(5.1)))
    }

    func testRecentScansDedupeAndLimit() {
        var recents = KitoRecentScans(limit: 3)
        for raw in ["one", "two", "three", "two", "four"] { recents.add(KitoScannedCode(raw: raw)) }
        XCTAssertEqual(recents.codes.map(\.raw), ["four", "two", "three"])
        recents.remove(recents.codes[1])
        XCTAssertEqual(recents.codes.map(\.raw), ["four", "three"])
        recents.clear()
        XCTAssertTrue(recents.codes.isEmpty)
    }
}

final class KitoCodeImageTests: XCTestCase {
    func testQRMatrixHasFinders() throws {
        let matrix = try XCTUnwrap(KitoQRMatrix("https://kito.dev", correction: .medium))
        XCTAssertEqual((matrix.size - 21) % 4, 0, "QR sizes are 21 + 4n")
        for origin in matrix.finderOrigins {
            XCTAssertTrue(matrix[origin.row, origin.column])
            XCTAssertTrue(matrix[origin.row + 6, origin.column + 6])
            XCTAssertFalse(matrix[origin.row + 1, origin.column + 1])
            XCTAssertTrue(matrix[origin.row + 3, origin.column + 3])
        }
        XCTAssertTrue(matrix.isFinder(row: 0, column: 0))
        XCTAssertTrue(matrix.isFinder(row: matrix.size - 1, column: 6))
        XCTAssertFalse(matrix.isFinder(row: matrix.size - 1, column: matrix.size - 1))
        XCTAssertFalse(matrix[-1, 0])
    }

    func testHigherCorrectionIsNotSmaller() throws {
        let low = try XCTUnwrap(KitoQRMatrix("kitopay://till/832910?amount=450", correction: .low))
        let high = try XCTUnwrap(KitoQRMatrix("kitopay://till/832910?amount=450", correction: .high))
        XCTAssertGreaterThanOrEqual(high.size, low.size)
    }

    func testLogoArea() throws {
        let matrix = try XCTUnwrap(KitoQRMatrix(size: 25, modules: Array(repeating: true, count: 625)))
        XCTAssertTrue(matrix.isUnderLogo(row: 12, column: 12, fraction: 0.2))
        XCTAssertFalse(matrix.isUnderLogo(row: 2, column: 12, fraction: 0.2))
        XCTAssertFalse(matrix.isUnderLogo(row: 12, column: 12, fraction: 0))
        XCTAssertNil(KitoQRMatrix(size: 3, modules: [true]))
    }

    func testTrimRemovesQuietZone() throws {
        var dark = Array(repeating: false, count: 36)
        for index in [14, 15, 20, 21] { dark[index] = true }
        let matrix = try XCTUnwrap(KitoQRMatrix.trimmed(dark, width: 6))
        XCTAssertEqual(matrix.size, 2)
        XCTAssertTrue(matrix[1, 1])
    }

    func testEAN13Modules() throws {
        let modules = try XCTUnwrap(KitoEAN13.modules(for: "5901234123457"))
        XCTAssertEqual(modules.count, 95)
        XCTAssertEqual(Array(modules.prefix(3)), [true, false, true])
        XCTAssertEqual(Array(modules[45..<50]), [false, true, false, true, false])
        XCTAssertEqual(Array(modules.suffix(3)), [true, false, true])
        // First digit 5 → parity LGGLLG; the digit after it (9) is L-coded: 0001011.
        XCTAssertEqual(Array(modules[3..<10]), [false, false, false, true, false, true, true])
        XCTAssertEqual(KitoEAN13.modules(for: "616100123456"), KitoEAN13.modules(for: "6161001234567"))
        XCTAssertNil(KitoEAN13.modules(for: "12345"))
        XCTAssertTrue(KitoEAN13.isGuard(46))
        XCTAssertFalse(KitoEAN13.isGuard(10))
    }
}
