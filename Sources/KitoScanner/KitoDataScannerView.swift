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
            do {
                try scanner.startScanning()
            } catch {
                // Not during the view update: the fallback changes state.
                DispatchQueue.main.async { onUnavailable() }
            }
            reportZoom(scanner)
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

    private func reportZoom(_ scanner: DataScannerViewController) {
        let low = scanner.minZoomFactor
        let high = max(scanner.maxZoomFactor, low)
        let factor = scanner.zoomFactor
        DispatchQueue.main.async { onZoom(factor, low...min(high, 10)) }
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: KitoDataScannerView

        init(parent: KitoDataScannerView) {
            self.parent = parent
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
