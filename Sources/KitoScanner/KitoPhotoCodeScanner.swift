//
//  KitoPhotoCodeScanner.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import PhotosUI
import KitoCore

/// The scanner without a camera: pick a photo (or a sample) and it finds the codes in it with
/// Vision, highlights them, and hands them back.
struct KitoPhotoCodeScanner: View {
    let reason: KitoScanFallbackReason
    let symbologies: Set<KitoSymbology>
    let accent: Color
    let isPaused: Bool
    let onDetect: (KitoScannedCode) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var detections: [KitoDetectedCode] = []
    @State private var chosen: UUID?
    @State private var isWorking = false
    @State private var message: String?
    @State private var sampleIndex = 0

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            header
            stage
                .frame(maxWidth: 340)
            if let message {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            buttons
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: message)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: isPaused) { _, paused in
            if !paused { chosen = nil }
        }
    }

    private var samples: [(raw: String, symbology: KitoSymbology)] {
        let allowed = KitoScannerSamples.payloads.filter { symbologies.contains($0.symbology) }
        return allowed.isEmpty ? KitoScannerSamples.payloads : allowed
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: theme.spacing.xs) {
            Image(systemName: reason.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(accent.opacity(0.35)))
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .accessibilityHidden(true)
            Text(reason.title).font(theme.typography.titleMedium.weight(.bold)).foregroundStyle(.white)
            Text(reason.message)
                .font(theme.typography.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var stage: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white.opacity(0.06))
                if let image {
                    photo(image, in: proxy.size)
                } else {
                    placeholder(in: proxy.size)
                }
                if isWorking {
                    KitoLaserLine(window: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 12, dy: 12), color: accent, isPaused: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func placeholder(in size: CGSize) -> some View {
        ZStack {
            KitoCornerBrackets(window: CGRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28))
                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            VStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 54, weight: .light)).foregroundStyle(.white.opacity(0.8))
                Text("Your photo appears here").font(theme.typography.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityHidden(true)
    }

    private func photo(_ image: UIImage, in size: CGSize) -> some View {
        let frame = KitoScanGeometry.aspectFitRect(content: image.size, in: size)
        return ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .accessibilityLabel("Chosen photo")
            ForEach(detections) { detection in
                box(for: detection, imageFrame: frame)
            }
        }
    }

    private func box(for detection: KitoDetectedCode, imageFrame: CGRect) -> some View {
        let rect = KitoScanGeometry.highlightRect(around: KitoScanGeometry.viewRect(forVisionBox: detection.boundingBox, imageFrame: imageFrame), padding: 6)
        let isChosen = chosen == detection.id
        return Button { pick(detection) } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((isChosen ? theme.colors.success : accent).opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isChosen ? theme.colors.success : Color.white, lineWidth: 3))
                .shadow(color: (isChosen ? theme.colors.success : accent).opacity(0.7), radius: 8)
        }
        .buttonStyle(KitoScanPressStyle(scale: 0.94))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel("\(detection.code.payload.kind.title): \(detection.code.payload.summary)")
        .accessibilityHint("Opens this code")
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }

    private var buttons: some View {
        VStack(spacing: theme.spacing.xs) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                KitoScanActionLabel(title: "Choose a photo", systemImage: "photo.on.rectangle", prominent: true, accent: accent, onDark: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(KitoScanPressStyle())
            HStack(spacing: theme.spacing.xs) {
                Button { useSample() } label: {
                    KitoScanActionLabel(title: "Use sample code", systemImage: "wand.and.stars", accent: accent, onDark: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
                if reason == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button { openURL(settings) } label: {
                        KitoScanActionLabel(title: "Settings", systemImage: "gear", accent: accent, onDark: true)
                    }
                    .buttonStyle(KitoScanPressStyle())
                }
            }
        }
        .frame(maxWidth: 340)
        .disabled(isWorking || isPaused)
        .opacity(isPaused ? 0.5 : 1)
    }

    // MARK: Work

    private func load(_ item: PhotosPickerItem) async {
        message = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) else {
            message = "That photo couldn't be opened."
            return
        }
        await scan(KitoImageTools.downscaled(picked), fallback: nil)
        pickerItem = nil
    }

    private func useSample() {
        let list = samples
        let sample = list[sampleIndex % list.count]
        sampleIndex += 1
        Task { await scan(KitoScannerSamples.image(for: sample.raw, symbology: sample.symbology), fallback: sample) }
    }

    /// Finds codes; a sample falls back to its known payload if detection isn't available.
    private func scan(_ picked: UIImage, fallback: (raw: String, symbology: KitoSymbology)?) async {
        detections = []
        chosen = nil
        image = picked
        isWorking = true
        message = nil
        async let found = KitoCodeDetector.detect(in: picked, symbologies: symbologies)
        if !reduceMotion { try? await Task.sleep(for: .seconds(0.7)) }
        let results = await found
        isWorking = false
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3)) { detections = results }
        if results.count == 1, let only = results.first {
            pick(only)
        } else if results.count > 1 {
            message = "Found \(results.count) codes. Tap the one you want."
        } else if let fallback {
            onDetect(KitoScannedCode(raw: fallback.raw, symbology: fallback.symbology))
        } else {
            message = "No code found. Try a sharper photo, closer to the code."
        }
    }

    private func pick(_ detection: KitoDetectedCode) {
        chosen = detection.id
        onDetect(detection.code)
    }
}
