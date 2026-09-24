//
//  KitoScanGeometry.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CoreGraphics
import Foundation

/// The layout maths behind the scanner overlays, kept pure so it can be tested.
public enum KitoScanGeometry {
    /// The scanning window: centred horizontally, nudged above centre, `widthFraction` of the
    /// width (capped at `maxWidth`) and shaped by `aspectRatio` (width ÷ height). It never
    /// exceeds 80% of the height.
    public static func cutout(in size: CGSize, aspectRatio: CGFloat = 1, widthFraction: CGFloat = 0.7,
                              maxWidth: CGFloat = 300, verticalBias: CGFloat = -0.06) -> CGRect {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return .zero }
        var width = min(size.width * widthFraction, maxWidth)
        var height = width / aspectRatio
        let maxHeight = size.height * 0.8
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }
        let x = (size.width - width) / 2
        let centreY = size.height / 2 + size.height * verticalBias
        let y = min(max(centreY - height / 2, 0), size.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// How long each corner bracket arm is: 18% of the short side, between 18 and 44 points.
    public static func bracketLength(for rect: CGRect) -> CGFloat {
        min(max(min(rect.width, rect.height) * 0.18, 18), 44)
    }

    /// The laser's distance from the top of the window for an animation progress that runs
    /// 0 → 1 → 2 … : it sweeps down, then back up (a triangle wave), staying `inset` from the edges.
    public static func laserOffset(progress: Double, height: CGFloat, inset: CGFloat = 8) -> CGFloat {
        let travel = max(height - inset * 2, 0)
        let phase = progress.truncatingRemainder(dividingBy: 2)
        let wave = phase <= 1 ? phase : 2 - phase
        return inset + travel * CGFloat(abs(wave))
    }

    /// Where `content` lands when fitted inside `container` without cropping.
    public static func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        return centred(CGSize(width: content.width * scale, height: content.height * scale), in: container)
    }

    /// Where `content` lands when it fills `container`, cropping the overflow.
    public static func aspectFillRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = max(container.width / content.width, container.height / content.height)
        return centred(CGSize(width: content.width * scale, height: content.height * scale), in: container)
    }

    static func centred(_ size: CGSize, in container: CGSize) -> CGRect {
        CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Converts a Vision bounding box (normalised, origin bottom-left) into the rect it covers
    /// on screen, given where the image is drawn.
    public static func viewRect(forVisionBox box: CGRect, imageFrame: CGRect) -> CGRect {
        CGRect(x: imageFrame.minX + box.minX * imageFrame.width,
               y: imageFrame.minY + (1 - box.maxY) * imageFrame.height,
               width: box.width * imageFrame.width,
               height: box.height * imageFrame.height)
    }

    /// Whether a detected code sits in the scanning window: its centre inside the window
    /// grown by `tolerance` points on each side.
    public static func isInside(_ codeRect: CGRect, window: CGRect, tolerance: CGFloat = 12) -> Bool {
        window.insetBy(dx: -tolerance, dy: -tolerance).contains(CGPoint(x: codeRect.midX, y: codeRect.midY))
    }

    /// A highlight rect around a detected code: padded, and never smaller than `minimum`.
    public static func highlightRect(around rect: CGRect, padding: CGFloat = 8, minimum: CGFloat = 44) -> CGRect {
        let padded = rect.insetBy(dx: -padding, dy: -padding)
        let width = max(padded.width, minimum)
        let height = max(padded.height, minimum)
        return CGRect(x: padded.midX - width / 2, y: padded.midY - height / 2, width: width, height: height)
    }
}

/// Decides which detections become scans: in continuous mode the same code is ignored until
/// `cooldown` seconds have passed, so holding the camera still doesn't fire it again and again.
public struct KitoScanThrottle: Sendable {
    public var cooldown: TimeInterval
    private var lastSeen: [String: Date] = [:]

    public init(cooldown: TimeInterval = 2.5) {
        self.cooldown = cooldown
    }

    /// True when `raw` should be reported now; records it either way.
    public mutating func shouldAccept(_ raw: String, at date: Date = Date()) -> Bool {
        defer { lastSeen[raw] = date }
        guard let previous = lastSeen[raw] else { return true }
        return date.timeIntervalSince(previous) >= cooldown
    }

    public mutating func reset() { lastSeen = [:] }
}

/// Keeps the most recent scans, newest first, without duplicates.
public struct KitoRecentScans: Sendable {
    public private(set) var codes: [KitoScannedCode] = []
    public var limit: Int

    public init(limit: Int = 12) {
        self.limit = max(limit, 1)
    }

    /// Adds a scan at the front; a scan of the same content moves up instead of repeating.
    public mutating func add(_ code: KitoScannedCode) {
        codes.removeAll { $0.raw == code.raw }
        codes.insert(code, at: 0)
        if codes.count > limit { codes.removeLast(codes.count - limit) }
    }

    public mutating func remove(_ code: KitoScannedCode) {
        codes.removeAll { $0.id == code.id }
    }

    public mutating func clear() { codes = [] }
}
