//
//  KitoCodeScanner.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A live QR and barcode scanner.
///
/// Uses VisionKit's data scanner where the device supports it and AVFoundation otherwise. Where
/// there's no camera (the Simulator) or access is denied it scans codes in photos instead, with
/// a "Use sample code" button so it can always be tried.
///
///     KitoCodeScanner(overlay: .laser) { code in
///         print(code.payload)
///     }
///
/// Needs `NSCameraUsageDescription` (and `NSPhotoLibraryUsageDescription` for the photo picker
/// on older systems) in the app's Info.plist.
public struct KitoCodeScanner: View {
    private let symbologies: Set<KitoSymbology>
    private let overlay: KitoScanOverlayStyle
    private let mode: KitoScanMode
    private let engine: KitoScannerEngine
    private let showsRecents: Bool
    private let showsResultCard: Bool
    private let hint: String?
    private let tint: Color?
    private let onPay: ((KitoPaymentRequest) -> Void)?
    private let onScan: (KitoScannedCode) -> Void
    private let onClose: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = KitoCodeScannerModel()
    @State private var pinchBase: CGFloat = 1

    /// - Parameters:
    ///   - symbologies: What to look for. Fewer is faster.
    ///   - overlay: How the scanning window looks.
    ///   - mode: Stop at the first code, or keep scanning.
    ///   - engine: Camera engine; `.automatic` picks the best available.
    ///   - showsRecents: Shows a tray of recent scans in continuous mode.
    ///   - showsResultCard: Shows a `KitoScanResultCard` for each scan.
    ///   - hint: Text under the window. Defaults to one that fits the symbologies.
    ///   - tint: Accent colour; the theme's primary by default.
    ///   - onPay: Passed to the result card's Pay button for payment codes.
    ///   - onScan: Called with each accepted scan.
    ///   - onClose: Shows a close button when set.
    public init(symbologies: Set<KitoSymbology> = KitoSymbology.all,
                overlay: KitoScanOverlayStyle = .corners,
                mode: KitoScanMode = .singleShot,
                engine: KitoScannerEngine = .automatic,
                showsRecents: Bool = true,
                showsResultCard: Bool = true,
                hint: String? = nil,
                tint: Color? = nil,
                onPay: ((KitoPaymentRequest) -> Void)? = nil,
                onScan: @escaping (KitoScannedCode) -> Void = { _ in },
                onClose: (() -> Void)? = nil) {
        self.symbologies = symbologies.isEmpty ? KitoSymbology.all : symbologies
        self.overlay = overlay
        self.mode = mode
        self.engine = engine
        self.showsRecents = showsRecents
        self.showsResultCard = showsResultCard
        self.hint = hint
        self.tint = tint
        self.onPay = onPay
        self.onScan = onScan
        self.onClose = onClose
    }

    private var accent: Color { theme.accent(tint) }

    public var body: some View {
        ZStack {
            Group {
                Color.black.ignoresSafeArea()
                if model.phase.isLive || model.phase == .checking {
                    GeometryReader { proxy in
                        liveLayer(size: proxy.size)
                    }
                    .ignoresSafeArea()
                } else {
                    KitoScanBackdrop(accent: accent)
                }
                chrome
            }
            .environment(\.colorScheme, .dark)
            if showsResultCard, mode == .singleShot, let code = model.current {
                resultOverlay(code)
            }
        }
        .task {
            model.mode = mode
            model.limitsToWindow = overlay.limitsToWindow
            model.onAccepted = onScan
            await model.prepare(engine: engine, symbologies: symbologies)
        }
        .onDisappear { model.stop() }
        .sensoryFeedback(.success, trigger: model.scanCount)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2), value: model.current)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3), value: model.highlight)
        .sheet(item: $model.selected) { code in
            ScrollView {
                KitoScanResultCard(code: code, tint: tint, onPay: onPay, onDismiss: { model.selected = nil })
                    .padding()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(\.kitoTheme, theme)
        }
    }

    // MARK: Live camera

    private func window(in size: CGSize) -> CGRect {
        if symbologies.isLinearOnly {
            return KitoScanGeometry.cutout(in: size, aspectRatio: 1.8, widthFraction: 0.84, maxWidth: 360, verticalBias: -0.08)
        }
        return KitoScanGeometry.cutout(in: size, aspectRatio: 1, widthFraction: 0.68, maxWidth: 290, verticalBias: -0.08)
    }

    @ViewBuilder
    private func liveLayer(size: CGSize) -> some View {
        let rect = window(in: size)
        ZStack {
            camera(window: rect)
            if model.phase.isLive {
                KitoScanOverlay(style: overlay, window: rect, accent: accent, isLocked: model.highlight != nil || model.isPaused)
                if let highlight = model.highlight {
                    KitoDetectionHighlight(rect: highlight, color: theme.colors.success)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                hintLabel.position(x: rect.midX, y: rect.maxY + 36)
            }
        }
        .onAppear { updateWindow(rect) }
        .onChange(of: rect) { _, newValue in updateWindow(newValue) }
    }

    private func updateWindow(_ rect: CGRect) {
        model.window = rect
        model.updateRegionOfInterest()
    }

    @ViewBuilder
    private func camera(window rect: CGRect) -> some View {
        switch model.phase {
        case .checking:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .visionKit:
            KitoDataScannerView(symbologies: symbologies, isScanning: !model.isPaused, zoom: model.zoom,
                                regionOfInterest: overlay.limitsToWindow ? rect : nil,
                                onDetect: { model.handle($0) },
                                onZoom: { factor, range in
                                    model.zoomRange = range
                                    model.zoom = factor
                                },
                                onUnavailable: { model.startAVFoundation() })
        case .avFoundation:
            KitoMetadataPreview(scanner: model.metadata)
                .gesture(pinch)
        case .photos:
            EmptyView()
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in model.setZoom(pinchBase * value.magnification) }
            .onEnded { _ in pinchBase = model.zoom }
    }

    private var hintLabel: some View {
        Text(model.isPaused ? "Got it" : (hint ?? defaultHint))
            .font(theme.typography.label.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
            .contentTransition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var defaultHint: String {
        if symbologies.isLinearOnly { return "Line up the barcode" }
        if symbologies.allSatisfy(\.isTwoDimensional) { return "Point at a QR code" }
        return "Point at a QR code or barcode"
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: theme.spacing.sm) {
            topBar
            if mode == .continuous, let code = model.current {
                KitoScanBanner(code: code, accent: accent) { model.selected = code }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if case .photos(let reason) = model.phase {
                KitoPhotoCodeScanner(reason: reason, symbologies: symbologies, accent: accent, isPaused: model.isPaused) { code in
                    model.deliver(code)
                }
                .padding(.horizontal, theme.spacing.lg)
            } else {
                Spacer(minLength: 0)
            }
            if model.phase.isLive, !(showsResultCard && model.current != nil && mode == .singleShot) {
                zoomPicker
            }
            if showsRecents, mode == .continuous, !model.recents.codes.isEmpty {
                KitoRecentScansTray(codes: model.recents.codes, accent: accent,
                                    onSelect: { model.selected = $0 },
                                    onClear: { model.clearRecents() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2), value: model.recents.codes.map(\.id))
    }

    private var topBar: some View {
        HStack {
            if let onClose {
                KitoScanChromeButton(systemImage: "xmark", label: "Close scanner", action: onClose)
            }
            Spacer()
            if model.phase.isLive, model.hasTorch {
                KitoScanChromeButton(systemImage: model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                     label: model.torchOn ? "Turn torch off" : "Turn torch on",
                                     isOn: model.torchOn) { model.toggleTorch() }
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.top, theme.spacing.sm)
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var zoomPicker: some View {
        let options = [1.0, 2.0, 3.0].filter { model.zoomRange.contains($0) }
        if options.count > 1 {
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { factor in
                    zoomChip(factor)
                }
            }
            .padding(6)
            .background(Capsule().fill(.black.opacity(0.4)))
            .padding(.bottom, theme.spacing.sm)
        }
    }

    private func zoomChip(_ factor: CGFloat) -> some View {
        let isCurrent = abs(model.zoom - factor) < 0.15
        return Button {
            model.setZoom(factor)
            pinchBase = model.zoom
        } label: {
            Text("\(Int(factor))×")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Color.yellow : Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(isCurrent ? 0.18 : 0.08)))
        }
        .buttonStyle(KitoScanPressStyle(scale: 0.9))
        .accessibilityLabel("Zoom \(Int(factor)) times")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: Result

    private func resultOverlay(_ code: KitoScannedCode) -> some View {
        VStack(spacing: theme.spacing.sm) {
            Spacer()
            KitoScanResultCard(code: code, tint: tint, onPay: onPay)
            Button { model.resume() } label: {
                KitoScanActionLabel(title: "Scan again", systemImage: "viewfinder", prominent: true, accent: accent, onDark: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(KitoScanPressStyle())
        }
        .padding(theme.spacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// "Scanned: Mama Mboga Greens" at the top in continuous mode.
struct KitoScanBanner: View {
    let code: KitoScannedCode
    let accent: Color
    let onTap: () -> Void
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                KitoKindBadge(kind: code.payload.kind, accent: accent, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(code.payload.kind.title).font(theme.typography.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(code.payload.summary).font(theme.typography.label.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(KitoScanPressStyle())
        .padding(.horizontal, theme.spacing.lg)
        .accessibilityLabel("Scanned \(code.payload.kind.title), \(code.payload.summary). Open")
    }
}

/// The horizontal tray of recent scans.
struct KitoRecentScansTray: View {
    let codes: [KitoScannedCode]
    let accent: Color
    let onSelect: (KitoScannedCode) -> Void
    let onClear: () -> Void
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack {
                Text("Recent scans").font(theme.typography.label.weight(.semibold)).foregroundStyle(.white)
                Text("\(codes.count)")
                    .font(theme.typography.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white))
                    .contentTransition(.numericText())
                Spacer()
                Button("Clear", action: onClear)
                    .font(theme.typography.label)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, theme.spacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(codes) { code in
                        chip(code).transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, theme.spacing.md)
            }
        }
        .padding(.vertical, theme.spacing.sm)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func chip(_ code: KitoScannedCode) -> some View {
        Button { onSelect(code) } label: {
            HStack(spacing: 8) {
                KitoKindBadge(kind: code.payload.kind, accent: accent, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(code.payload.kind.title).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                    Text(code.payload.summary).font(.footnote.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(KitoScanPressStyle())
        .accessibilityLabel("\(code.payload.kind.title), \(code.payload.summary)")
        .accessibilityHint("Shows the scan")
    }
}
