//
//  KitoScannerSamples.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit

/// Ready-made codes and images for trying the scanners without a camera (the Simulator,
/// previews, demos). Every image is drawn on device; nothing is bundled.
public enum KitoScannerSamples {
    public static let payment = KitoPaymentRequest(kind: .till, number: "832910", amount: 450, merchant: "Mama Mboga Greens", note: "Sukuma, nyanya, dhania")
    public static let paybill = KitoPaymentRequest(kind: .paybill, number: "247247", account: "KTH-0042", amount: 2_500, merchant: "Kilimani Heights Water")
    public static let wifi = KitoWiFiNetwork(ssid: "Kahawa House Guest", password: "karibu2026")
    public static let website = "https://wyksoftsinc.com"
    public static let contact = KitoContactCard(name: "Achieng Owuor", organization: "Safari Tech", jobTitle: "Product designer",
                                                phones: ["+254 712 345 678"], emails: ["achieng@example.co.ke"],
                                                address: "Kenyatta Avenue, Nairobi", website: "https://example.co.ke")
    public static let event = KitoScannedEvent(title: "Nairobi Tech Week", start: eventStart, end: eventStart.addingTimeInterval(8 * 3_600),
                                                location: "KICC, Nairobi", notes: "Hall B. Bring your badge.")
    public static let place = KitoGeoPoint(latitude: -1.28638, longitude: 36.81723, query: "Kenyatta Avenue, Nairobi")
    public static let message = KitoTextMessage(number: "+254712345678", body: "Nimefika, niko gate")
    /// A valid Kenyan (616) EAN-13.
    public static let product = "6161001234567"

    /// 14 Oct 2026, 09:00 in Nairobi (06:00 UTC).
    static var eventStart: Date { Date(timeIntervalSince1970: 1_791_957_600) }

    /// The payloads "Use sample code" cycles through, in order.
    public static let payloads: [(raw: String, symbology: KitoSymbology)] = [
        (payment.payload, .qr),
        (wifi.payload, .qr),
        (product, .ean13),
        (contact.vCard, .qr),
        (website, .qr),
        (event.payload, .qr),
        (place.payload, .qr),
        (message.payload, .qr),
        (paybill.payload, .qr),
    ]

    /// The sample payloads as scans.
    public static var codes: [KitoScannedCode] {
        payloads.map { KitoScannedCode(raw: $0.raw, symbology: $0.symbology) }
    }

    /// A photo-like scene with the payload printed as a code on a sticker: a QR code, or a
    /// barcode for 12/13-digit products.
    @MainActor
    public static func image(for raw: String, symbology: KitoSymbology = .qr, caption: String? = nil) -> UIImage {
        let payload = KitoCodeParser.parse(raw, symbology: symbology)
        let scene = KitoSampleScene(raw: raw, payload: payload, isBarcode: symbology == .ean13, caption: caption)
            .frame(width: 900, height: 1_125)
        return render(scene)
    }

    /// A debit card with a Luhn-valid test number, for trying the card scanner.
    @MainActor
    public static func cardImage() -> UIImage {
        render(KitoSampleCard().frame(width: 1_012, height: 638))
    }

    /// What the sample card says, for when on-device text recognition isn't available.
    public static let cardLines = ["KITO BANK", "DEBIT", "4242 4242 4242 4242", "VALID THRU 08/29", "ACHIENG W OWUOR"]

    /// Two scanned-looking pages: a market receipt and a service-charge invoice.
    @MainActor
    public static func documentPages() -> [UIImage] {
        [render(KitoSampleReceipt().frame(width: 900, height: 1_273)),
         render(KitoSampleInvoice().frame(width: 900, height: 1_273))]
    }

    @MainActor
    static func render<Content: View>(_ view: Content) -> UIImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }
}

// MARK: - Scenes

private struct KitoSampleScene: View {
    let raw: String
    let payload: KitoCodePayload
    let isBarcode: Bool
    let caption: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: backdrop, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.08)).frame(width: 700).offset(x: -300, y: -420)
            Circle().fill(Color.black.opacity(0.12)).frame(width: 600).offset(x: 340, y: 480)
            sticker.rotationEffect(.degrees(-3))
        }
    }

    private var backdrop: [Color] {
        switch payload.kind {
        case .payment: return [Color(red: 0.05, green: 0.45, blue: 0.29), Color(red: 0.02, green: 0.22, blue: 0.16)]
        case .wifi: return [Color(red: 0.42, green: 0.26, blue: 0.16), Color(red: 0.2, green: 0.12, blue: 0.08)]
        case .product: return [Color(red: 0.93, green: 0.55, blue: 0.2), Color(red: 0.7, green: 0.3, blue: 0.1)]
        case .event: return [Color(red: 0.3, green: 0.2, blue: 0.6), Color(red: 0.12, green: 0.08, blue: 0.3)]
        default: return [Color(red: 0.12, green: 0.32, blue: 0.55), Color(red: 0.05, green: 0.12, blue: 0.25)]
        }
    }

    private var title: String {
        switch payload {
        case .payment(let request): return request.merchant ?? "Lipa na KitoPay"
        case .wifi(let network): return network.ssid
        case .product: return "Pure Highland Honey"
        case .contact(let card): return card.name
        case .event(let event): return event.title
        default: return payload.kind.title
        }
    }

    private var subtitle: String {
        if let caption { return caption }
        switch payload {
        case .payment(let request): return "\(request.kind.title) \(request.number)"
        case .wifi: return "Scan to join the Wi-Fi"
        case .product: return "500 g · Product of Kenya"
        case .contact: return "Scan to save my details"
        default: return "Scan me"
        }
    }

    private var sticker: some View {
        VStack(spacing: 26) {
            Text(title).font(.system(size: 50, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.5)
            code
            Text(subtitle).font(.system(size: 32, weight: .semibold)).foregroundStyle(Color(white: 0.3))
            if case .payment = payload {
                Text("LIPA NA KITOPAY").font(.system(size: 26, weight: .black)).tracking(4)
                    .foregroundStyle(.white).padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(Color(red: 0.05, green: 0.45, blue: 0.29)))
            }
        }
        .padding(48)
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 48, style: .continuous).fill(Color.white))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 20)
    }

    @ViewBuilder
    private var code: some View {
        if isBarcode {
            KitoBarcodeView(ean13: raw).frame(width: 500)
        } else if let matrix = KitoQRMatrix(raw, correction: .medium) {
            Image(uiImage: matrix.image(moduleSize: 10))
                .interpolation(.none)
                .resizable()
                .frame(width: 480, height: 480)
        }
    }
}

private struct KitoSampleCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.04, green: 0.36, blue: 0.3), Color(red: 0.02, green: 0.14, blue: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.07)).frame(width: 760).offset(x: 480, y: -300)
            Circle().fill(Color.white.opacity(0.05)).frame(width: 520).offset(x: -180, y: 360)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("KITO BANK").font(.system(size: 44, weight: .heavy)).tracking(3)
                    Spacer()
                    Text("DEBIT").font(.system(size: 34, weight: .bold)).opacity(0.8)
                }
                RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.82, blue: 0.5), Color(red: 0.75, green: 0.6, blue: 0.3)],
                                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 92).padding(.top, 56)
                Text("4242 4242 4242 4242").font(.system(size: 76, weight: .semibold, design: .monospaced)).padding(.top, 44)
                HStack(spacing: 18) {
                    Text("VALID THRU").font(.system(size: 22, weight: .bold)).opacity(0.75)
                    Text("08/29").font(.system(size: 44, weight: .semibold, design: .monospaced))
                }
                .padding(.top, 22)
                Text("ACHIENG W OWUOR").font(.system(size: 44, weight: .semibold)).tracking(2).padding(.top, 20)
            }
            .foregroundStyle(.white)
            .padding(56)
        }
        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
    }
}

/// Warm paper with uneven light, so the scan filters have something to clean up.
private struct KitoPaper<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.97, green: 0.95, blue: 0.9)
            content.padding(70)
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.clear, Color(red: 0.4, green: 0.3, blue: 0.1).opacity(0.12)], center: .center, startRadius: 300, endRadius: 800)
        }
    }
}

private struct KitoSampleReceipt: View {
    private let items: [(String, String, Int)] = [
        ("Sukuma wiki", "2 bunches", 60), ("Tomatoes", "1 kg", 120), ("Red onions", "½ kg", 70),
        ("Dhania", "1 bunch", 20), ("Avocados", "4", 120), ("Ripe bananas", "6", 60),
    ]

    var body: some View {
        KitoPaper {
            VStack(alignment: .leading, spacing: 22) {
                Text("MAMA MBOGA GREENS").font(.system(size: 50, weight: .black)).tracking(2)
                Text("Kilimani Market, Stall 14 · Till 832910").font(.system(size: 26))
                Text("Receipt #0419 · 24 Sep 2026, 08:12").font(.system(size: 26)).opacity(0.7)
                Rectangle().frame(height: 3).padding(.vertical, 10)
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0).font(.system(size: 32, weight: .semibold))
                        Text(item.1).font(.system(size: 26)).opacity(0.6)
                        Spacer()
                        Text("\(item.2)").font(.system(size: 32, design: .monospaced))
                    }
                }
                Rectangle().frame(height: 3).padding(.vertical, 10)
                HStack {
                    Text("TOTAL (KES)").font(.system(size: 38, weight: .heavy))
                    Spacer()
                    Text("450").font(.system(size: 44, weight: .heavy, design: .monospaced))
                }
                Text("Paid with KitoPay · Ref QK7X2M9LPA").font(.system(size: 26)).opacity(0.7)
                Spacer()
                Text("Asante! Karibu tena.").font(.system(size: 34, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color(white: 0.1))
        }
    }
}

private struct KitoSampleInvoice: View {
    var body: some View {
        KitoPaper {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kilimani Heights").font(.system(size: 46, weight: .heavy))
                        Text("Residents' Association").font(.system(size: 28)).opacity(0.7)
                    }
                    Spacer()
                    Text("INVOICE").font(.system(size: 40, weight: .black)).tracking(3)
                }
                Text("INV-2026-0042 · Due 5 Oct 2026").font(.system(size: 26)).opacity(0.7).padding(.top, 10)
                Text("Billed to: Apt B4, Mr B. Mwangi").font(.system(size: 28, weight: .semibold))
                Rectangle().frame(height: 3).padding(.vertical, 12)
                row("Service charge, October", "6,500")
                row("Water (18 m³)", "1,980")
                row("Security levy", "1,200")
                row("Garbage collection", "300")
                Rectangle().frame(height: 3).padding(.vertical, 12)
                row("Total due (KES)", "9,980", size: 36, weight: .heavy)
                Text("Pay via Paybill 247247, account KTH-0042.").font(.system(size: 28)).padding(.top, 16)
                Text("Thank you for keeping our estate clean and safe.").font(.system(size: 26)).opacity(0.7)
                Spacer()
            }
            .foregroundStyle(Color(white: 0.1))
        }
    }

    private func row(_ label: String, _ amount: String, size: CGFloat = 30, weight: Font.Weight = .regular) -> some View {
        HStack {
            Text(label).font(.system(size: size, weight: weight))
            Spacer()
            Text(amount).font(.system(size: size, weight: weight, design: .monospaced))
        }
    }
}
