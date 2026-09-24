//
//  KitoDataScannerView.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
@preconcurrency import VisionKit
@preconcurrency import Vision

/// VisionKit's `DataScannerViewController`, the preferred engine on devices that support it.
struct KitoDataScannerView: UIViewControllerRepresentable {
    let symbologies: Set<KitoSymbology>
    var isScanning: Bool
    var zoom: CGFloat
    var regionOfInterest: CGRect?
    let onDetect: (KitoLiveDetection) -> Void
    let onZoom: (_ factor: CGFloat, _ range: ClosedRange<CGFloat>) -> Void
    let onUnavailable: () -> Void

    /// Whether this device and app can use the data scanner right now.
    @MainActor
    static var isUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let wanted = symbologies.visionSymbologies
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: wanted)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        scanner.view.backgroundColor = .black
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if isScanning, !scanner.isScanning {
            // Outside the view update: starting reports zoom, which changes state.
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak scanner] in
                guard let scanner else { return }
                coordinator.start(scanner, attemptsLeft: 20)
            }
        } else if !isScanning, scanner.isScanning {
            scanner.stopScanning()
        }
        let clamped = min(max(zoom, scanner.minZoomFactor), scanner.maxZoomFactor)
        if abs(scanner.zoomFactor - clamped) > 0.01 { scanner.zoomFactor = clamped }
        if scanner.regionOfInterest != regionOfInterest { scanner.regionOfInterest = regionOfInterest }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: KitoDataScannerView

        init(parent: KitoDataScannerView) {
            self.parent = parent
        }

        /// Starts once the scanner is on screen; the data scanner can't start before that.
        func start(_ scanner: DataScannerViewController, attemptsLeft: Int) {
            guard !scanner.isScanning, parent.isScanning else { return }
            guard scanner.view.window != nil else {
                guard attemptsLeft > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak scanner] in
                    guard let self, let scanner else { return }
                    self.start(scanner, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            do {
                try scanner.startScanning()
                let low = scanner.minZoomFactor
                parent.onZoom(scanner.zoomFactor, low...min(max(scanner.maxZoomFactor, low), 10))
            } catch {
                parent.onUnavailable()
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue, !value.isEmpty else { continue }
                let symbology = KitoSymbology(vision: barcode.observation.symbology)
                parent.onDetect(KitoLiveDetection(raw: value, symbology: symbology, frame: Self.frame(of: barcode.bounds)))
            }
        }

        func dataScannerDidZoom(_ dataScanner: DataScannerViewController) {
            let low = dataScanner.minZoomFactor
            let high = max(dataScanner.maxZoomFactor, low)
            parent.onZoom(dataScanner.zoomFactor, low...min(high, 10))
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            parent.onUnavailable()
        }

        static func frame(of bounds: RecognizedItem.Bounds) -> CGRect {
            let points = [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft]
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let minX = xs.min() ?? 0
            let minY = ys.min() ?? 0
            return CGRect(x: minX, y: minY, width: (xs.max() ?? minX) - minX, height: (ys.max() ?? minY) - minY)
        }
    }
}
