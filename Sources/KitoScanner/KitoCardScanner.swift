//
//  KitoCardScanner.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import PhotosUI
import KitoCore

/// Reads a payment card from a photo: the number (Luhn-checked, then masked to its last four
/// digits), expiry and cardholder name. Text recognition runs on device; the photo is dropped
/// as soon as it's read and the full number is never kept.
///
///     KitoCardScanner { details in
///         form.last4 = details.last4
///         form.expiry = details.expiry
///     }
public struct KitoCardScanner: View {
    private let tint: Color?
    private let onScan: (KitoCardDetails) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: UIImage?
    @State private var details: KitoCardDetails?
    @State private var isReading = false
    @State private var message: String?
    @State private var usedSampleText = false
    @State private var showsCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmations = 0

    public init(tint: Color? = nil, onScan: @escaping (KitoCardDetails) -> Void = { _ in }) {
        self.tint = tint
        self.onScan = onScan
    }

    private var accent: Color { theme.accent(tint) }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            VStack(spacing: theme.spacing.xs) {
                Text(details == nil ? "Scan a card" : "Check the details")
                    .font(theme.typography.titleLarge.weight(.bold))
                    .foregroundStyle(theme.colors.onBackground)
                    .contentTransition(.opacity)
                Label("Read on this device. The full number is never stored.", systemImage: "lock.shield.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.onBackground.opacity(0.65))
            }
            stage
            if let message {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
                    .multilineTextAlignment(.center)
            }
            if let details {
                KitoCardFacts(details: details, accent: accent, usedSampleText: usedSampleText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(theme.spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25), value: details)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: message)
        .sensoryFeedback(.success, trigger: confirmations)
        .fullScreenCover(isPresented: $showsCamera) {
            KitoStillCamera { image in
                showsCamera = false
                if let image { Task { await read(image, sample: false) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await read(image, sample: false)
                } else {
                    message = "That photo couldn't be opened."
                }
                pickerItem = nil
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            let window = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                if let details {
                    KitoCardFace(details: details, accent: accent)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                } else if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Card photo")
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(theme.colors.surfaceMuted)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "creditcard.viewfinder").font(.system(size: 42, weight: .light))
                                Text("Fill the frame with the front of the card").font(theme.typography.caption)
                            }
                            .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                        )
                }
                if details == nil {
                    KitoCornerBrackets(window: window.insetBy(dx: -6, dy: -6), radius: 24)
                        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                if isReading {
                    KitoLaserLine(window: window, color: accent, isPaused: false)
                }
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .frame(maxWidth: 380)
    }

    private var buttons: some View {
        let cameraAvailable = KitoStillCamera.isAvailable
        return VStack(spacing: theme.spacing.xs) {
            if let details {
                Button {
                    confirmations += 1
                    onScan(details)
                } label: {
                    KitoScanActionLabel(title: "Use this card", systemImage: "checkmark", prominent: true, accent: accent).frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
                Button { reset() } label: {
                    KitoScanActionLabel(title: "Scan again", systemImage: "arrow.counterclockwise", accent: accent).frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
            } else {
                if cameraAvailable {
                    Button { showsCamera = true } label: {
                        KitoScanActionLabel(title: "Take a photo", systemImage: "camera.fill", prominent: true, accent: accent).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KitoScanPressStyle())
                }
                HStack(spacing: theme.spacing.xs) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        KitoScanActionLabel(title: "Choose photo", systemImage: "photo", prominent: !cameraAvailable, accent: accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KitoScanPressStyle())
                    Button { Task { await read(KitoScannerSamples.cardImage(), sample: true) } } label: {
                        KitoScanActionLabel(title: "Sample card", systemImage: "wand.and.stars", accent: accent).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KitoScanPressStyle())
                }
            }
        }
        .frame(maxWidth: 380)
        .disabled(isReading)
    }

    // MARK: Work

    private func read(_ image: UIImage, sample: Bool) async {
        message = nil
        details = nil
        usedSampleText = false
        photo = KitoImageTools.downscaled(image, maxDimension: 1_600)
        isReading = true
        let source = photo ?? image
        async let lines = KitoTextRecognizer.lines(in: source)
        if !reduceMotion { try? await Task.sleep(for: .seconds(0.9)) }
        var found = KitoCardTextParser.details(from: await lines)
        if found == nil, sample {
            // Text recognition isn't available everywhere (some simulators); the sample still demos.
            found = KitoCardTextParser.details(from: KitoScannerSamples.cardLines)
            usedSampleText = found != nil
        }
        isReading = false
        // The photo shows the whole number, so it goes as soon as it's been read.
        photo = nil
        if let found {
            details = found
        } else {
            message = "Couldn't find a valid card number. Try again in good light with the card filling the frame."
        }
    }

    private func reset() {
        details = nil
        message = nil
        photo = nil
        usedSampleText = false
    }
}

/// A clean card face drawn from the masked details.
struct KitoCardFace: View {
    let details: KitoCardDetails
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [accent, accent.opacity(0.65), Color.black.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.08)).frame(width: 260).offset(x: 180, y: -120)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(red: 0.96, green: 0.84, blue: 0.52), Color(red: 0.76, green: 0.6, blue: 0.3)],
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 32)
                    Spacer()
                    Text(details.brand.title).font(.system(size: 16, weight: .heavy, design: .rounded)).italic()
                }
                Spacer()
                Text(details.maskedNumber)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer().frame(height: 14)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARDHOLDER").font(.system(size: 9, weight: .bold)).opacity(0.7)
                        Text(details.holderName?.uppercased() ?? "—").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EXPIRES").font(.system(size: 9, weight: .bold)).opacity(0.7)
                        Text(details.expiry?.formatted ?? "—").font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: accent.opacity(0.35), radius: 18, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(details.brand.title) ending \(details.last4.map(String.init).joined(separator: " "))"]
        if let expiry = details.expiry { parts.append("expires \(expiry.formatted)") }
        if let name = details.holderName { parts.append(name) }
        return parts.joined(separator: ", ")
    }
}

/// Checks under the card: number valid, expiry, where the text came from.
struct KitoCardFacts: View {
    let details: KitoCardDetails
    let accent: Color
    let usedSampleText: Bool
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            fact(details.isNumberValid ? "Number passes the Luhn check" : "Number failed the Luhn check",
                 systemImage: details.isNumberValid ? "checkmark.seal.fill" : "xmark.seal.fill",
                 color: details.isNumberValid ? theme.colors.success : theme.colors.danger)
            if let expiry = details.expiry {
                let expired = expiry.isExpired()
                fact(expired ? "Expired \(expiry.formatted)" : "Valid through \(expiry.formatted)",
                     systemImage: expired ? "calendar.badge.exclamationmark" : "calendar",
                     color: expired ? theme.colors.danger : theme.colors.onSurface.opacity(0.7))
            } else {
                fact("No expiry found", systemImage: "calendar.badge.clock", color: theme.colors.warning)
            }
            if usedSampleText {
                fact("Sample read from its printed text", systemImage: "text.viewfinder", color: theme.colors.onSurface.opacity(0.6))
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.xs)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).stroke(theme.colors.border, lineWidth: 1))
        .frame(maxWidth: 380)
    }

    private func fact(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(color).frame(width: 22)
            Text(text).font(theme.typography.label).foregroundStyle(theme.colors.onSurface)
            Spacer()
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// The system camera for a single still.
struct KitoStillCamera: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    @MainActor
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
