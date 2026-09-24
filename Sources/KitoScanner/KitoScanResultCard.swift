//
//  KitoScanResultCard.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import MapKit
import KitoCore

/// Shows what a scanned code contains, with the actions that make sense for it: open a link,
/// join a Wi-Fi network (or copy its password), add a contact, call, email, text, open a
/// place in Maps, add an event, pay, or look up a product.
///
///     KitoScanResultCard(code: code, onPay: { request in startCheckout(request) })
public struct KitoScanResultCard: View {
    private let code: KitoScannedCode
    private let tint: Color?
    private let onPay: ((KitoPaymentRequest) -> Void)?
    private let onDismiss: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedID: String?
    @State private var revealsPassword = false
    @State private var notice: String?
    @State private var isJoining = false
    @State private var showsContact = false
    @State private var showsEvent = false
    @State private var feedback = 0

    /// - Parameters:
    ///   - code: The scan to show.
    ///   - tint: Accent for the badge and main action; the theme's primary by default.
    ///   - onPay: Called by the Pay button on payment codes. Without it the card offers to copy the number.
    ///   - onDismiss: Shows a close button when set.
    public init(code: KitoScannedCode, tint: Color? = nil, onPay: ((KitoPaymentRequest) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.code = code
        self.tint = tint
        self.onPay = onPay
        self.onDismiss = onDismiss
    }

    private var accent: Color { theme.accent(tint) }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            header
            KitoResultDetail(payload: code.payload, accent: accent, revealsPassword: $revealsPassword)
            if let notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.onSurface.opacity(0.8))
                    .padding(theme.spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(theme.colors.surfaceMuted))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            actionRow
        }
        .padding(theme.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                .fill(theme.colors.surface)
                .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).stroke(theme.colors.border, lineWidth: 1))
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: notice)
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(isPresented: $showsContact) {
            if case .contact(let card) = code.payload {
                KitoNewContactSheet(card: card) { showsContact = false }.ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showsEvent) {
            if case .event(let event) = code.payload {
                KitoEventEditSheet(event: event) { showsEvent = false }.ignoresSafeArea()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            KitoKindBadge(kind: code.payload.kind, accent: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(code.payload.kind.title.uppercased())
                    .font(theme.typography.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Text(headline)
                    .font(theme.typography.titleMedium.weight(.bold))
                    .foregroundStyle(theme.colors.onSurface)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let symbology = code.symbology {
                Text(symbology.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.colors.surfaceMuted))
                    .accessibilityLabel("\(symbology.title) code")
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.colors.onSurface.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(theme.colors.surfaceMuted))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KitoScanPressStyle(scale: 0.9))
                .accessibilityLabel("Close")
            }
        }
    }

    private var headline: String {
        switch code.payload {
        case .url(let url): return url.host ?? url.absoluteString
        case .wifi(let network): return network.ssid
        case .contact(let card): return card.name
        case .phone(let number): return number
        case .email(let message): return message.address
        case .sms(let message): return message.number
        case .geo(let point): return point.query ?? point.coordinateText
        case .event(let event): return event.title
        case .payment(let request): return request.merchant ?? request.kind.title
        case .product(let product): return product.kind.title
        case .text(let text): return text.count > 40 ? String(text.prefix(40)) + "…" : text
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.xs) {
                ForEach(actions) { action in
                    actionButton(action)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func actionButton(_ action: KitoResultAction) -> some View {
        switch action.behaviour {
        case .run(let perform):
            Button(action: perform) {
                KitoScanActionLabel(title: copiedID == action.id ? "Copied" : action.title,
                                    systemImage: copiedID == action.id ? "checkmark" : action.systemImage,
                                    prominent: action.prominent, accent: accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(KitoScanPressStyle())
            .disabled(action.id == "join" && isJoining)
        case .share(let text):
            ShareLink(item: text) {
                KitoScanActionLabel(title: action.title, systemImage: action.systemImage, prominent: action.prominent, accent: accent)
            }
            .buttonStyle(KitoScanPressStyle())
        }
    }

    private var actions: [KitoResultAction] {
        switch code.payload {
        case .url(let url): return urlActions(url)
        case .wifi(let network): return wifiActions(network)
        case .contact(let card): return contactActions(card)
        case .phone(let number): return phoneActions(number)
        case .email(let message): return emailActions(message)
        case .sms(let message): return smsActions(message)
        case .geo(let point): return geoActions(point)
        case .event(let event): return eventActions(event)
        case .payment(let request): return paymentActions(request)
        case .product(let product): return productActions(product)
        case .text(let text): return [copy(text, title: "Copy text", prominent: true), .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", behaviour: .share(text))]
        }
    }

    private func urlActions(_ url: URL) -> [KitoResultAction] {
        [KitoResultAction(id: "open", title: "Open link", systemImage: "safari.fill", prominent: true, behaviour: .run { openURL(url) }),
         copy(url.absoluteString, title: "Copy link"),
         KitoResultAction(id: "share", title: "Share", systemImage: "square.and.arrow.up", behaviour: .share(url.absoluteString))]
    }

    private func wifiActions(_ network: KitoWiFiNetwork) -> [KitoResultAction] {
        var result: [KitoResultAction] = []
        if KitoWiFiJoiner.isAvailable {
            result.append(KitoResultAction(id: "join", title: isJoining ? "Joining…" : "Join network", systemImage: "wifi", prominent: true,
                                           behaviour: .run { join(network) }))
        }
        if let password = network.password {
            result.append(copy(password, title: "Copy password", prominent: result.isEmpty, id: "password",
                               note: KitoWiFiJoiner.isAvailable ? nil : "Password copied. Open Settings › Wi-Fi and choose \(network.ssid)."))
        }
        result.append(copy(network.ssid, title: "Copy name", id: "ssid"))
        return result
    }

    private func contactActions(_ card: KitoContactCard) -> [KitoResultAction] {
        var result = [KitoResultAction(id: "add", title: "Add contact", systemImage: "person.crop.circle.badge.plus", prominent: true,
                                       behaviour: .run { showsContact = true })]
        if let phone = card.phones.first, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
            result.append(KitoResultAction(id: "call", title: "Call", systemImage: "phone.fill", behaviour: .run { openURL(url) }))
        }
        if let email = card.emails.first, let url = KitoEmailMessage(address: email).url {
            result.append(KitoResultAction(id: "email", title: "Email", systemImage: "envelope.fill", behaviour: .run { openURL(url) }))
        }
        result.append(KitoResultAction(id: "share", title: "Share", systemImage: "square.and.arrow.up", behaviour: .share(code.raw)))
        return result
    }

    private func phoneActions(_ number: String) -> [KitoResultAction] {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        var result: [KitoResultAction] = []
        if let url = URL(string: "tel:\(digits)") {
            result.append(KitoResultAction(id: "call", title: "Call", systemImage: "phone.fill", prominent: true, behaviour: .run { openURL(url) }))
        }
        if let url = URL(string: "sms:\(digits)") {
            result.append(KitoResultAction(id: "message", title: "Message", systemImage: "message.fill", behaviour: .run { openURL(url) }))
        }
        result.append(copy(number, title: "Copy number"))
        return result
    }

    private func emailActions(_ message: KitoEmailMessage) -> [KitoResultAction] {
        var result: [KitoResultAction] = []
        if let url = message.url {
            result.append(KitoResultAction(id: "compose", title: "Write email", systemImage: "square.and.pencil", prominent: true, behaviour: .run { openURL(url) }))
        }
        result.append(copy(message.address, title: "Copy address"))
        return result
    }

    private func smsActions(_ message: KitoTextMessage) -> [KitoResultAction] {
        var result: [KitoResultAction] = []
        if let url = message.url {
            result.append(KitoResultAction(id: "send", title: "Send message", systemImage: "paperplane.fill", prominent: true, behaviour: .run { openURL(url) }))
        }
        result.append(copy(message.number, title: "Copy number"))
        return result
    }

    private func geoActions(_ point: KitoGeoPoint) -> [KitoResultAction] {
        var result: [KitoResultAction] = []
        if let url = point.mapsURL {
            result.append(KitoResultAction(id: "maps", title: "Open in Maps", systemImage: "map.fill", prominent: true, behaviour: .run { openURL(url) }))
        }
        result.append(copy(point.coordinateText, title: "Copy coordinates"))
        return result
    }

    private func eventActions(_ event: KitoScannedEvent) -> [KitoResultAction] {
        [KitoResultAction(id: "calendar", title: "Add to calendar", systemImage: "calendar.badge.plus", prominent: true, behaviour: .run { showsEvent = true }),
         KitoResultAction(id: "share", title: "Share", systemImage: "square.and.arrow.up", behaviour: .share(event.title))]
    }

    private func paymentActions(_ request: KitoPaymentRequest) -> [KitoResultAction] {
        var result: [KitoResultAction] = []
        if let onPay {
            let title = request.formattedAmount.map { "Pay \($0)" } ?? "Pay"
            result.append(KitoResultAction(id: "pay", title: title, systemImage: "checkmark.shield.fill", prominent: true, behaviour: .run {
                feedback += 1
                onPay(request)
            }))
        }
        result.append(copy(request.number, title: "Copy \(request.kind.title.lowercased())", prominent: onPay == nil, id: "number"))
        if let account = request.account { result.append(copy(account, title: "Copy account", id: "account")) }
        return result
    }

    private func productActions(_ product: KitoProductCode) -> [KitoResultAction] {
        var result: [KitoResultAction] = []
        if let url = URL(string: "https://www.google.com/search?q=\(product.digits)") {
            result.append(KitoResultAction(id: "lookup", title: "Look up", systemImage: "magnifyingglass", prominent: true, behaviour: .run { openURL(url) }))
        }
        result.append(copy(product.digits, title: "Copy number"))
        return result
    }

    private func copy(_ text: String, title: String, prominent: Bool = false, id: String = "copy", note: String? = nil) -> KitoResultAction {
        KitoResultAction(id: id, title: title, systemImage: "doc.on.doc", prominent: prominent, behaviour: .run {
            KitoPasteboard.copy(text)
            feedback += 1
            copiedID = id
            if let note { notice = note }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                if copiedID == id { copiedID = nil }
            }
        })
    }

    private func join(_ network: KitoWiFiNetwork) {
        isJoining = true
        Task { @MainActor in
            let outcome = await KitoWiFiJoiner.join(network)
            isJoining = false
            switch outcome {
            case .joined:
                feedback += 1
                notice = "Joined \(network.ssid)."
            case .cancelled:
                notice = nil
            case .failed(let reason):
                if let password = network.password {
                    KitoPasteboard.copy(password)
                    notice = "\(reason) Password copied: open Settings › Wi-Fi and choose \(network.ssid)."
                } else {
                    notice = "\(reason) Open Settings › Wi-Fi and choose \(network.ssid)."
                }
            }
        }
    }
}

/// One button on the result card.
struct KitoResultAction: Identifiable {
    enum Behaviour {
        case run(() -> Void)
        case share(String)
    }

    let id: String
    let title: String
    let systemImage: String
    var prominent = false
    let behaviour: Behaviour
}

// MARK: - Detail

/// The body of the card for each payload.
struct KitoResultDetail: View {
    let payload: KitoCodePayload
    let accent: Color
    @Binding var revealsPassword: Bool
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        switch payload {
        case .url(let url): urlDetail(url)
        case .wifi(let network): wifiDetail(network)
        case .contact(let card): contactDetail(card)
        case .phone(let number): KitoResultRow(label: "Number", value: number, systemImage: "phone")
        case .email(let message): emailDetail(message)
        case .sms(let message): smsDetail(message)
        case .geo(let point): KitoResultMap(point: point, accent: accent)
        case .event(let event): eventDetail(event)
        case .payment(let request): paymentDetail(request)
        case .product(let product): productDetail(product)
        case .text(let text):
            Text(text)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.onSurface)
                .lineLimit(8)
                .textSelection(.enabled)
        }
    }

    private func urlDetail(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(url.absoluteString)
                .font(theme.typography.caption.monospaced())
                .foregroundStyle(theme.colors.onSurface.opacity(0.7))
                .lineLimit(3)
                .textSelection(.enabled)
            if url.scheme?.lowercased() != "https" {
                Label("Not a secure link. Check it before you open it.", systemImage: "exclamationmark.shield.fill")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.warning)
            }
        }
    }

    private func wifiDetail(_ network: KitoWiFiNetwork) -> some View {
        VStack(spacing: 0) {
            KitoResultRow(label: "Security", value: network.security.title, systemImage: "lock")
            if let password = network.password {
                Divider().overlay(theme.colors.border)
                HStack {
                    KitoResultRow(label: "Password", value: revealsPassword ? password : String(repeating: "•", count: min(password.count, 12)),
                                  systemImage: "key", monospaced: true)
                    Button {
                        revealsPassword.toggle()
                    } label: {
                        Image(systemName: revealsPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(accent)
                            .frame(width: 44, height: 44)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                }
            }
            if network.isHidden {
                Divider().overlay(theme.colors.border)
                KitoResultRow(label: "Network", value: "Hidden", systemImage: "eye.slash")
            }
        }
    }

    private func contactDetail(_ card: KitoContactCard) -> some View {
        VStack(spacing: 0) {
            if let line = [card.jobTitle, card.organization].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                KitoResultRow(label: "Works at", value: line, systemImage: "briefcase")
            }
            ForEach(card.phones, id: \.self) { KitoResultRow(label: "Phone", value: $0, systemImage: "phone") }
            ForEach(card.emails, id: \.self) { KitoResultRow(label: "Email", value: $0, systemImage: "envelope") }
            if let address = card.address { KitoResultRow(label: "Address", value: address, systemImage: "mappin") }
        }
    }

    private func emailDetail(_ message: KitoEmailMessage) -> some View {
        VStack(spacing: 0) {
            if let subject = message.subject { KitoResultRow(label: "Subject", value: subject, systemImage: "text.bubble") }
            if let body = message.body { KitoResultRow(label: "Message", value: body, systemImage: "text.alignleft") }
        }
    }

    private func smsDetail(_ message: KitoTextMessage) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if let body = message.body {
                Text(body)
                    .font(theme.typography.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(accent))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func eventDetail(_ event: KitoScannedEvent) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            if let start = event.start {
                VStack(spacing: 0) {
                    Text(start.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(theme.typography.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(accent)
                    Text(start.formatted(.dateTime.day()))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.colors.onSurface)
                        .padding(.vertical, 4)
                }
                .frame(width: 58)
                .background(theme.colors.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(KitoEventFormatting.when(event))
                    .font(theme.typography.bodyEmphasized)
                    .foregroundStyle(theme.colors.onSurface)
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.onSurface.opacity(0.7))
                }
                if let notes = event.notes {
                    Text(notes).font(theme.typography.caption).foregroundStyle(theme.colors.onSurface.opacity(0.6)).lineLimit(3)
                }
            }
        }
    }

    private func paymentDetail(_ request: KitoPaymentRequest) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if let amount = request.formattedAmount {
                Text(amount)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.colors.onSurface)
                    .contentTransition(.numericText())
            }
            VStack(spacing: 0) {
                KitoResultRow(label: request.kind.title, value: request.number, systemImage: "number", monospaced: true)
                if let account = request.account { KitoResultRow(label: "Account", value: account, systemImage: "person.text.rectangle", monospaced: true) }
                if let note = request.note { KitoResultRow(label: "For", value: note, systemImage: "text.bubble") }
            }
        }
    }

    private func productDetail(_ product: KitoProductCode) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if product.digits.count == 13 {
                KitoBarcodeView(ean13: product.digits).frame(maxWidth: 240).frame(maxWidth: .infinity)
            } else {
                Text(product.digits).font(.system(size: 28, weight: .semibold, design: .monospaced)).foregroundStyle(theme.colors.onSurface)
            }
            HStack(spacing: theme.spacing.xs) {
                Label(product.isValid ? "Check digit OK" : "Check digit doesn't match",
                      systemImage: product.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(product.isValid ? theme.colors.success : theme.colors.danger)
                if let region = product.region {
                    Text("· \(region)").font(theme.typography.caption).foregroundStyle(theme.colors.onSurface.opacity(0.6))
                }
            }
        }
    }
}

/// A label, value and icon on one line.
struct KitoResultRow: View {
    let label: String
    let value: String
    var systemImage: String
    var monospaced = false
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onSurface.opacity(0.6))
            Spacer(minLength: theme.spacing.sm)
            Text(value)
                .font(monospaced ? theme.typography.body.monospaced() : theme.typography.body)
                .foregroundStyle(theme.colors.onSurface)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A small, still map with a pin.
struct KitoResultMap: View {
    let point: KitoGeoPoint
    let accent: Color
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200)),
                interactionModes: []) {
                Marker(point.query ?? "Pin", coordinate: coordinate).tint(accent)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
            .accessibilityLabel("Map of \(point.query ?? point.coordinateText)")
            Text(point.coordinateText)
                .font(theme.typography.caption.monospaced())
                .foregroundStyle(theme.colors.onSurface.opacity(0.6))
        }
    }
}

enum KitoEventFormatting {
    /// "Wed 14 Oct, 09:00 – 17:00" or "Wed 14 Oct · All day".
    static func when(_ event: KitoScannedEvent) -> String {
        guard let start = event.start else { return "Date to be confirmed" }
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if event.isAllDay { return "\(day) · All day" }
        let startTime = start.formatted(date: .omitted, time: .shortened)
        guard let end = event.end else { return "\(day), \(startTime)" }
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        let endText = sameDay ? end.formatted(date: .omitted, time: .shortened) : end.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "\(day), \(startTime) – \(endText)"
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
