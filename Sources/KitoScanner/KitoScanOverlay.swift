//
//  KitoScanOverlay.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// How the scanning window is drawn over the camera.
public enum KitoScanOverlayStyle: String, CaseIterable, Hashable, Sendable {
    /// Four rounded brackets that breathe, then snap tight when a code is read.
    case corners
    /// A glowing line sweeping up and down the window.
    case laser
    /// A rounded cut-out with the rest of the feed dimmed.
    case frame
    /// A small reticle and nothing else; the whole feed scans.
    case minimal

    public var title: String {
        switch self {
        case .corners: return "Corners"
        case .laser: return "Laser"
        case .frame: return "Frame"
        case .minimal: return "Minimal"
        }
    }

    /// Whether detection is limited to the window.
    var limitsToWindow: Bool { self != .minimal }
}

/// Draws the overlay for a style over a window rect (in the overlay's own coordinates).
struct KitoScanOverlay: View {
    let style: KitoScanOverlayStyle
    let window: CGRect
    let accent: Color
    var isLocked: Bool
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        ZStack {
            switch style {
            case .corners:
                KitoCutoutShape(window: window, radius: 26).fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                KitoBreathingBrackets(window: window, color: bracketColor, isLocked: isLocked)
            case .laser:
                KitoCutoutShape(window: window, radius: 22).fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
                KitoCornerBrackets(window: window, radius: 22).stroke(bracketColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                KitoLaserLine(window: window, color: isLocked ? theme.colors.success : accent, isPaused: isLocked)
            case .frame:
                KitoCutoutShape(window: window, radius: 24).fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isLocked ? theme.colors.success : Color.white, lineWidth: isLocked ? 4 : 2)
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
            case .minimal:
                KitoReticle(color: bracketColor, isLocked: isLocked)
                    .position(x: window.midX, y: window.midY)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: isLocked)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bracketColor: Color { isLocked ? theme.colors.success : .white }
}

/// The whole area with a rounded hole; fill it with `eoFill` to dim around the window.
struct KitoCutoutShape: Shape {
    let window: CGRect
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -2, dy: -2))
        path.addRoundedRect(in: window, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}

/// Four L-shaped brackets with rounded elbows.
struct KitoCornerBrackets: Shape {
    let window: CGRect
    var radius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let length = KitoScanGeometry.bracketLength(for: window)
        let r = min(radius, length * 0.8)
        var path = Path()
        addCorner(&path, corner: CGPoint(x: window.minX, y: window.minY), dx: 1, dy: 1, length: length, radius: r)
        addCorner(&path, corner: CGPoint(x: window.maxX, y: window.minY), dx: -1, dy: 1, length: length, radius: r)
        addCorner(&path, corner: CGPoint(x: window.maxX, y: window.maxY), dx: -1, dy: -1, length: length, radius: r)
        addCorner(&path, corner: CGPoint(x: window.minX, y: window.maxY), dx: 1, dy: -1, length: length, radius: r)
        return path
    }

    private func addCorner(_ path: inout Path, corner: CGPoint, dx: CGFloat, dy: CGFloat, length: CGFloat, radius: CGFloat) {
        let start = CGPoint(x: corner.x, y: corner.y + dy * length)
        let end = CGPoint(x: corner.x + dx * length, y: corner.y)
        path.move(to: start)
        path.addArc(tangent1End: corner, tangent2End: end, radius: radius)
        path.addLine(to: end)
    }
}

/// Brackets that gently breathe while searching and snap in when a code is read.
struct KitoBreathingBrackets: View {
    let window: CGRect
    let color: Color
    let isLocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || isLocked {
            brackets(expansion: isLocked && !reduceMotion ? -10 : 0)
        } else {
            TimelineView(.animation) { context in
                brackets(expansion: breathingExpansion(at: context.date))
            }
        }
    }

    private func brackets(expansion: CGFloat) -> some View {
        KitoCornerBrackets(window: window.insetBy(dx: -expansion, dy: -expansion))
            .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.35), radius: 6)
    }

    /// 0 → 5 → 0 points every 1.8 seconds.
    private func breathingExpansion(at date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
        let wave = (1 - cos(phase * 2 * .pi)) / 2
        return 5 * CGFloat(wave)
    }
}

/// The sweeping laser. With Reduce Motion it rests in the middle of the window.
struct KitoLaserLine: View {
    let window: CGRect
    let color: Color
    var isPaused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || isPaused {
            line.position(x: window.midX, y: window.midY)
        } else {
            TimelineView(.animation) { context in
                line.position(x: window.midX, y: window.minY + offset(at: context.date))
            }
        }
    }

    private func offset(at date: Date) -> CGFloat {
        let progress = date.timeIntervalSinceReferenceDate / 1.3
        return KitoScanGeometry.laserOffset(progress: progress, height: window.height, inset: 14)
    }

    private var line: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0), color.opacity(0.35), color.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(window.width - 20, 0), height: 26)
                .blur(radius: 10)
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0), color, .white, color, color.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(window.width - 28, 0), height: 2.5)
                .shadow(color: color, radius: 6)
        }
    }
}

/// A small reticle for the minimal style.
struct KitoReticle: View {
    let color: Color
    let isLocked: Bool

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.9), lineWidth: 2).frame(width: isLocked ? 30 : 40, height: isLocked ? 30 : 40)
            Circle().fill(color).frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
    }
}

/// A glowing box around the code that was just read.
struct KitoDetectionHighlight: View {
    let rect: CGRect
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color, lineWidth: 3))
            .shadow(color: color.opacity(0.6), radius: 10)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
