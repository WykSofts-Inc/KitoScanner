//
//  KitoCodeScannerModel.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// Whether the scanner stops after the first code or keeps going.
public enum KitoScanMode: String, CaseIterable, Hashable, Sendable {
    /// Stops on the first code and shows it; "Scan again" resumes.
    case singleShot
    /// Keeps scanning; each new code joins the recent-scans tray. The same code is ignored
    /// for a couple of seconds so it doesn't repeat while the camera is still on it.
    case continuous
}

/// Which camera engine to use.
public enum KitoScannerEngine: String, CaseIterable, Hashable, Sendable {
    /// VisionKit's data scanner when the device supports it, otherwise AVFoundation.
    case automatic
    /// Prefer VisionKit; falls back to AVFoundation where it isn't available.
    case visionKit
    /// Always AVFoundation's metadata output.
    case avFoundation
    /// No camera: scan codes in photos (and samples) only.
    case photos
}

/// Why the scanner is showing its photo fallback.
enum KitoScanFallbackReason: Equatable {
    case noCamera, denied, photosOnly

    var systemImage: String {
        switch self {
        case .noCamera: return "video.slash.fill"
        case .denied: return "lock.fill"
        case .photosOnly: return "photo.on.rectangle.angled"
        }
    }

    var title: String {
        switch self {
        case .noCamera: return "No camera here"
        case .denied: return "Camera access is off"
        case .photosOnly: return "Scan from a photo"
        }
    }

    var message: String {
        switch self {
        case .noCamera: return "Pick a photo with a code in it, or try a sample code."
        case .denied: return "Turn it on in Settings, or scan a code from a photo."
        case .photosOnly: return "Pick a screenshot or photo that has a QR code or barcode in it."
        }
    }
}

/// State behind `KitoCodeScanner`: which engine is live, what's been scanned, torch and zoom.
@MainActor
@Observable
final class KitoCodeScannerModel {
    enum Phase: Equatable {
        case checking, visionKit, avFoundation
        case photos(KitoScanFallbackReason)

        var isLive: Bool { self == .visionKit || self == .avFoundation }
    }

    private(set) var phase: Phase = .checking
    private(set) var recents = KitoRecentScans()
    /// The scan shown in the result card (single-shot) or banner (continuous).
    private(set) var current: KitoScannedCode?
    var selected: KitoScannedCode?
    private(set) var highlight: CGRect?
    private(set) var isPaused = false
    private(set) var torchOn = false
    private(set) var hasTorch = false
    var zoom: CGFloat = 1
    var zoomRange: ClosedRange<CGFloat> = 1...1
    private(set) var scanCount = 0

    @ObservationIgnored var mode: KitoScanMode = .singleShot
    @ObservationIgnored var limitsToWindow = true
    @ObservationIgnored var window: CGRect = .zero
    @ObservationIgnored var onAccepted: ((KitoScannedCode) -> Void)?
    @ObservationIgnored let metadata = KitoMetadataScanner()
    @ObservationIgnored private var throttle = KitoScanThrottle()
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var symbologies: Set<KitoSymbology> = KitoSymbology.all

    /// Picks an engine, asking for camera access if needed.
    func prepare(engine: KitoScannerEngine, symbologies: Set<KitoSymbology>) async {
        guard phase == .checking else { return }
        self.symbologies = symbologies
        if engine == .photos { phase = .photos(.photosOnly); return }
        switch await KitoCameraAccess.request() {
        case .noCamera: phase = .photos(.noCamera); return
        case .denied: phase = .photos(.denied); return
        case .authorized: break
        }
        hasTorch = KitoCameraAccess.hasTorch
        if engine != .avFoundation, KitoDataScannerView.isUsable {
            phase = .visionKit
        } else {
            startAVFoundation()
        }
    }

    /// Switches to AVFoundation, e.g. when the data scanner becomes unavailable.
    func startAVFoundation() {
        metadata.onDetect = { [weak self] detection in self?.handle(detection) }
        metadata.start(symbologies: symbologies)
        if metadata.status == .failed {
            phase = .photos(.noCamera)
        } else {
            phase = .avFoundation
            zoomRange = 1...max(metadata.maxZoom, 1)
            updateRegionOfInterest()
        }
    }

    func stop() {
        metadata.stop()
        if torchOn { toggleTorch() }
        highlightTask?.cancel()
        bannerTask?.cancel()
    }

    func updateRegionOfInterest() {
        guard phase == .avFoundation else { return }
        metadata.setRegionOfInterest(limitsToWindow && window != .zero ? window : nil)
    }

    /// A live detection from either engine.
    func handle(_ detection: KitoLiveDetection) {
        guard !isPaused else { return }
        if limitsToWindow, let frame = detection.frame, window != .zero,
           !KitoScanGeometry.isInside(frame, window: window, tolerance: 24) { return }
        guard throttle.shouldAccept(detection.raw) else { return }
        deliver(KitoScannedCode(raw: detection.raw, symbology: detection.symbology), frame: detection.frame, highlights: true)
    }

    /// Records a scan and tells the host app.
    func deliver(_ code: KitoScannedCode, frame: CGRect? = nil, highlights: Bool = false) {
        guard !isPaused else { return }
        recents.add(code)
        current = code
        scanCount += 1
        if mode == .singleShot { isPaused = true }
        if highlights {
            highlight = frame.map { KitoScanGeometry.highlightRect(around: $0) } ?? window
        }
        onAccepted?(code)
        AccessibilityNotification.Announcement("Scanned \(code.payload.kind.title): \(code.payload.summary)").post()
        scheduleClears()
    }

    private func scheduleClears() {
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled, let self, self.mode == .continuous else { return }
            self.highlight = nil
        }
        guard mode == .continuous else { return }
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// Clears the result and keeps scanning.
    func resume() {
        current = nil
        highlight = nil
        isPaused = false
        throttle.reset()
    }

    func toggleTorch() {
        let wanted = !torchOn
        torchOn = phase == .avFoundation ? metadata.setTorch(wanted) : KitoCameraAccess.setTorch(wanted)
    }

    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, zoomRange.lowerBound), zoomRange.upperBound)
        if phase == .avFoundation {
            metadata.setZoom(clamped)
            zoom = metadata.zoom
        } else {
            zoom = clamped
        }
    }

    func removeRecent(_ code: KitoScannedCode) { recents.remove(code) }
    func clearRecents() { recents.clear() }
}
