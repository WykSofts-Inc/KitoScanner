//
//  KitoQRMatrix.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// How much of a QR code can be damaged (or covered by a logo) and still scan.
public enum KitoQRCorrection: String, CaseIterable, Hashable, Sendable {
    /// ~7%
    case low = "L"
    /// ~15%
    case medium = "M"
    /// ~25%
    case quartile = "Q"
    /// ~30%, needed when a logo covers the middle.
    case high = "H"
}

/// The grid of dark and light modules in a QR code, without its quiet zone.
public struct KitoQRMatrix: Hashable, Sendable {
    /// Modules per side.
    public let size: Int
    let modules: [Bool]

    /// A matrix from row-major modules; `modules.count` must be `size * size`.
    public init?(size: Int, modules: [Bool]) {
        guard size > 0, modules.count == size * size else { return nil }
        self.size = size
        self.modules = modules
    }

    /// Encodes `content` with Core Image. Nil only if the content is too long for a QR code.
    public init?(_ content: String, correction: KitoQRCorrection = .medium) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = correction.rawValue
        guard let output = filter.outputImage, let grid = KitoQRMatrix.readModules(output) else { return nil }
        self = grid
    }

    /// True when the module is dark. Out-of-range positions are light.
    public subscript(row: Int, column: Int) -> Bool {
        guard (0..<size).contains(row), (0..<size).contains(column) else { return false }
        return modules[row * size + column]
    }

    /// Whether the module belongs to one of the three 7×7 finder patterns in the corners.
    public func isFinder(row: Int, column: Int) -> Bool {
        let nearTop = row < 7
        let nearLeft = column < 7
        let nearBottom = row >= size - 7
        let nearRight = column >= size - 7
        return (nearTop && nearLeft) || (nearTop && nearRight) || (nearBottom && nearLeft)
    }

    /// Whether the module falls under a centred logo covering `fraction` of the width.
    public func isUnderLogo(row: Int, column: Int, fraction: Double) -> Bool {
        guard fraction > 0 else { return false }
        let span = Int((Double(size) * fraction).rounded(.up)) | 1
        let start = (size - span) / 2
        return (start..<(start + span)).contains(row) && (start..<(start + span)).contains(column)
    }

    /// Top-left module of each finder pattern: (row, column).
    public var finderOrigins: [(row: Int, column: Int)] {
        [(0, 0), (0, size - 7), (size - 7, 0)]
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Reads Core Image's 1-pixel-per-module output and trims the quiet zone.
    static func readModules(_ image: CIImage) -> KitoQRMatrix? {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, width == height, let cgImage = context.createCGImage(image, from: extent) else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let bitmap = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            bitmap.interpolationQuality = .none
            bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let dark = pixels.map { $0 < 128 }
        return trimmed(dark, width: width)
    }

    /// Crops a square bitmap to the bounding box of its dark modules.
    static func trimmed(_ dark: [Bool], width: Int) -> KitoQRMatrix? {
        var minRow = width, maxRow = -1, minColumn = width, maxColumn = -1
        for row in 0..<width {
            for column in 0..<width where dark[row * width + column] {
                minRow = min(minRow, row); maxRow = max(maxRow, row)
                minColumn = min(minColumn, column); maxColumn = max(maxColumn, column)
            }
        }
        guard maxRow >= minRow, maxColumn >= minColumn else { return nil }
        let size = max(maxRow - minRow, maxColumn - minColumn) + 1
        var modules = [Bool](repeating: false, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                let sourceRow = minRow + row
                let sourceColumn = minColumn + column
                guard sourceRow < width, sourceColumn < width else { continue }
                modules[row * size + column] = dark[sourceRow * width + sourceColumn]
            }
        }
        return KitoQRMatrix(size: size, modules: modules)
    }

    /// A crisp black-on-white bitmap with a four-module quiet zone, for sharing or detection.
    public func image(moduleSize: CGFloat = 12, foreground: UIColor = .black, background: UIColor = .white) -> UIImage {
        let quiet = 4
        let side = CGFloat(size + quiet * 2) * moduleSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            foreground.setFill()
            for row in 0..<size {
                for column in 0..<size where self[row, column] {
                    context.fill(CGRect(x: CGFloat(column + quiet) * moduleSize, y: CGFloat(row + quiet) * moduleSize,
                                        width: moduleSize, height: moduleSize))
                }
            }
        }
    }
}

/// EAN-13 bar patterns, for drawing product barcodes (sample images, labels).
public enum KitoEAN13 {
    static let left = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    static let even = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    static let right = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    /// The 95 modules (true = bar) for a 13-digit code; a 12-digit body gets its check digit
    /// added. Nil for anything else.
    public static func modules(for code: String) -> [Bool]? {
        var digits = code
        if digits.count == 12, let full = KitoCheckDigits.appendingGTINCheckDigit(to: digits) { digits = full }
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 13, digits.count == 13 else { return nil }
        let pattern = Array(parity[values[0]])
        var bits = "101"
        for index in 1...6 {
            bits += pattern[index - 1] == "L" ? left[values[index]] : even[values[index]]
        }
        bits += "01010"
        for index in 7...12 { bits += right[values[index]] }
        bits += "101"
        return bits.map { $0 == "1" }
    }

    /// Whether module `index` is part of a guard pattern (drawn a little longer).
    public static func isGuard(_ index: Int) -> Bool {
        index < 3 || (45..<50).contains(index) || index >= 92
    }
}
