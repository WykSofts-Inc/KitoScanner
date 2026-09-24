//
//  KitoCodeDetector.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import UIKit
import CoreImage
@preconcurrency import Vision
@preconcurrency import AVFoundation

// MARK: - Symbology bridging

extension KitoSymbology {
    /// Vision's symbologies for this family.
    var visionSymbologies: [VNBarcodeSymbology] {
        switch self {
        case .qr: return [.qr, .microQR]
        case .aztec: return [.aztec]
        case .pdf417: return [.pdf417, .microPDF417]
        case .dataMatrix: return [.dataMatrix]
        case .ean13: return [.ean13]
        case .ean8: return [.ean8]
        case .upce: return [.upce]
        case .code128: return [.code128]
        case .code39: return [.code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum]
        case .code93: return [.code93, .code93i]
        case .itf14: return [.itf14, .i2of5, .i2of5Checksum]
        case .codabar: return [.codabar]
        }
    }

    /// AVFoundation's metadata types for this family.
    var metadataTypes: [AVMetadataObject.ObjectType] {
        switch self {
        case .qr: return [.qr, .microQR]
        case .aztec: return [.aztec]
        case .pdf417: return [.pdf417, .microPDF417]
        case .dataMatrix: return [.dataMatrix]
        case .ean13: return [.ean13]
        case .ean8: return [.ean8]
        case .upce: return [.upce]
        case .code128: return [.code128]
        case .code39: return [.code39, .code39Mod43]
        case .code93: return [.code93]
        case .itf14: return [.itf14, .interleaved2of5]
        case .codabar: return [.codabar]
        }
    }

    init?(vision symbology: VNBarcodeSymbology) {
        guard let match = KitoSymbology.allCases.first(where: { $0.visionSymbologies.contains(symbology) }) else { return nil }
        self = match
    }

    init?(metadata type: AVMetadataObject.ObjectType) {
        guard let match = KitoSymbology.allCases.first(where: { $0.metadataTypes.contains(type) }) else { return nil }
        self = match
    }
}

extension Set where Element == KitoSymbology {
    var visionSymbologies: [VNBarcodeSymbology] { flatMap(\.visionSymbologies) }
    var metadataTypes: [AVMetadataObject.ObjectType] { flatMap(\.metadataTypes) }
    /// True when every symbology is a 1D barcode, so the scan window can be wide and short.
    var isLinearOnly: Bool { !isEmpty && allSatisfy { !$0.isTwoDimensional } }
}

// MARK: - Still images

/// A code found in a still image, with where it is.
public struct KitoDetectedCode: Identifiable, Hashable, Sendable {
    public var id: UUID { code.id }
    public let code: KitoScannedCode
    /// Normalised to the image, origin bottom-left (Vision's convention). Use
    /// `KitoScanGeometry.viewRect(forVisionBox:imageFrame:)` to place it on screen.
    public let boundingBox: CGRect
}

/// Finds QR codes and barcodes in photos, on device.
public enum KitoCodeDetector {
    /// Every code in the image: Vision first, then Core Image's QR detector if Vision finds
    /// nothing or isn't available (as on some simulators).
    public static func detect(in image: UIImage, symbologies: Set<KitoSymbology> = KitoSymbology.all) async -> [KitoDetectedCode] {
        guard let cgImage = KitoImageTools.uprightCGImage(image) else { return [] }
        let wanted = symbologies
        return await Task.detached(priority: .userInitiated) {
            let found = visionCodes(in: cgImage, symbologies: wanted)
            if !found.isEmpty || !wanted.contains(.qr) { return found }
            return coreImageQRCodes(in: cgImage)
        }.value
    }

    static func visionCodes(in cgImage: CGImage, symbologies: Set<KitoSymbology>) -> [KitoDetectedCode] {
        let request = VNDetectBarcodesRequest()
        let supported = (try? request.supportedSymbologies()) ?? []
        let wanted = symbologies.visionSymbologies.filter { supported.isEmpty || supported.contains($0) }
        if !wanted.isEmpty { request.symbologies = wanted }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        var seen = Set<String>()
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty, seen.insert(payload).inserted else { return nil }
            let code = KitoScannedCode(raw: payload, symbology: KitoSymbology(vision: observation.symbology))
            return KitoDetectedCode(code: code, boundingBox: observation.boundingBox)
        }
    }

    static func coreImageQRCodes(in cgImage: CGImage) -> [KitoDetectedCode] {
        let ciImage = CIImage(cgImage: cgImage)
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options) else { return [] }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return [] }
        var seen = Set<String>()
        return detector.features(in: ciImage).compactMap { feature in
            guard let qr = feature as? CIQRCodeFeature, let message = qr.messageString, seen.insert(message).inserted else { return nil }
            let box = CGRect(x: (qr.bounds.minX - extent.minX) / extent.width, y: (qr.bounds.minY - extent.minY) / extent.height,
                             width: qr.bounds.width / extent.width, height: qr.bounds.height / extent.height)
            return KitoDetectedCode(code: KitoScannedCode(raw: message, symbology: .qr), boundingBox: box)
        }
    }
}

/// Reads text lines from an image with Vision, top to bottom.
public enum KitoTextRecognizer {
    public static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = KitoImageTools.uprightCGImage(image) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let accurate = recognize(cgImage, level: .accurate)
            return accurate.isEmpty ? recognize(cgImage, level: .fast) : accurate
        }.value
    }

    static func recognize(_ cgImage: CGImage, level: VNRequestTextRecognitionLevel) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let observations = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

enum KitoImageTools {
    /// The image's pixels with its orientation applied, so Vision boxes match what's on screen.
    static func uprightCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let redrawn = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return redrawn.cgImage
    }

    /// Scales large photos down so detection and filters stay quick.
    static func downscaled(_ image: UIImage, maxDimension: CGFloat = 2_000) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
