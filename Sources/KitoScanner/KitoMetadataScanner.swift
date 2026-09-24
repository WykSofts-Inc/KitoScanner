//
//  KitoMetadataScanner.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
@preconcurrency import AVFoundation

/// A detection from either engine: the payload, its symbology and where it is on screen.
struct KitoLiveDetection {
    let raw: String
    let symbology: KitoSymbology?
    /// In the preview's coordinate space; nil when the engine can't say.
    let frame: CGRect?
}

/// Camera access and torch helpers shared by both engines.
enum KitoCameraAccess {
    enum Result { case authorized, denied, noCamera }

    /// Asks for camera access if needed.
    @MainActor
    static func request() async -> Result {
        guard AVCaptureDevice.default(for: .video) != nil else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        default: return .denied
        }
    }

    static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    /// Turns the back camera's torch on or off. Returns the state it ended in.
    @discardableResult
    static func setTorch(_ on: Bool, device: AVCaptureDevice? = AVCaptureDevice.default(for: .video)) -> Bool {
        guard let device, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            if on, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            return on
        } catch {
            return false
        }
    }
}

/// Scans with `AVCaptureMetadataOutput`: the engine used when VisionKit's data scanner isn't
/// available (older devices, or when it's switched off).
@MainActor
@Observable
final class KitoMetadataScanner: NSObject {
    enum Status: Equatable { case idle, running, failed }

    private(set) var status: Status = .idle
    private(set) var zoom: CGFloat = 1
    private(set) var maxZoom: CGFloat = 1

    let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCaptureMetadataOutput()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private let queue = DispatchQueue(label: "kito.scanner.session")
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored var onDetect: ((KitoLiveDetection) -> Void)?

    /// Configures the session for `symbologies` and starts it. Call after access is granted.
    func start(symbologies: Set<KitoSymbology>) {
        guard status != .running else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { status = .failed; return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        let available = Set(output.availableMetadataObjectTypes)
        output.metadataObjectTypes = symbologies.metadataTypes.filter { available.contains($0) }
        output.setMetadataObjectsDelegate(self, queue: .main)
        session.commitConfiguration()
        self.device = device
        maxZoom = min(device.activeFormat.videoMaxZoomFactor, 6)
        if device.isFocusModeSupported(.continuousAutoFocus) || device.isAutoFocusRangeRestrictionSupported {
            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
        status = .running
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
        if status == .running { status = .idle }
    }

    func setTorch(_ on: Bool) -> Bool {
        KitoCameraAccess.setTorch(on, device: device)
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = min(max(factor, 1), maxZoom)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            zoom = clamped
        } catch {}
    }

    /// Limits detection to the window, given in the preview layer's coordinates.
    func setRegionOfInterest(_ rect: CGRect?) {
        guard let previewLayer else { return }
        let converted = rect.map { previewLayer.metadataOutputRectConverted(fromLayerRect: $0) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let session = session
        let output = output
        queue.async {
            guard session.isRunning || !session.outputs.isEmpty else { return }
            output.rectOfInterest = converted
        }
    }

    fileprivate func handle(_ objects: [AVMetadataObject]) {
        for object in objects {
            guard let code = object as? AVMetadataMachineReadableCodeObject, let value = code.stringValue, !value.isEmpty else { continue }
            let frame = previewLayer?.transformedMetadataObject(for: code)?.bounds
            onDetect?(KitoLiveDetection(raw: value, symbology: KitoSymbology(metadata: code.type), frame: frame))
        }
    }
}

extension KitoMetadataScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // The delegate queue is main, so this is already on the main actor.
        MainActor.assumeIsolated { handle(metadataObjects) }
    }
}

/// The live feed for the AVFoundation engine.
struct KitoMetadataPreview: UIViewRepresentable {
    let scanner: KitoMetadataScanner

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
        scanner.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        scanner.previewLayer = uiView.previewLayer
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // The layer class is fixed above, so this cast always succeeds.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer() }
    }
}
