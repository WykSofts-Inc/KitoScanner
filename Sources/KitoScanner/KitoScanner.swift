//
//  KitoScanner.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import KitoCore

// Small pieces shared by the views in this package.

extension KitoTheme {
    /// The tint a view was given, or the theme's primary colour.
    func accent(_ tint: Color?) -> Color { tint ?? colors.primary }
}

/// Scales down a little while pressed.
struct KitoScanPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A capsule action button: filled for the main action, outlined for the rest.
struct KitoScanActionLabel: View {
    let title: String
    let systemImage: String
    var prominent = false
    var accent: Color
    var onDark = false
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(theme.typography.label.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(foreground)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
            .contentShape(Capsule())
    }

    private var foreground: Color {
        if prominent { return onDark ? .black : theme.colors.onPrimary }
        return onDark ? .white : theme.colors.onSurface
    }

    private var fill: Color {
        if prominent { return onDark ? .white : accent }
        return onDark ? Color.white.opacity(0.12) : theme.colors.surfaceMuted
    }

    private var stroke: Color {
        if prominent { return .clear }
        return onDark ? Color.white.opacity(0.18) : theme.colors.border
    }
}

/// A round glass button for camera chrome (torch, close, flip).
struct KitoScanChromeButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    var onColor: Color = .yellow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolEffect(.bounce, value: isOn)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(isOn ? AnyShapeStyle(onColor) : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Circle().stroke(Color.white.opacity(isOn ? 0 : 0.2), lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
        .buttonStyle(KitoScanPressStyle(scale: 0.9))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The dark, softly lit backdrop behind camera fallbacks.
struct KitoScanBackdrop: View {
    var accent: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.13), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [accent.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

/// A little icon in a tinted rounded square, for payload kinds.
struct KitoKindBadge: View {
    let kind: KitoPayloadKind
    var accent: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: accent.opacity(0.35), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

enum KitoPasteboard {
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

extension View {
    /// Applies `transform` only when `condition` is true.
    @ViewBuilder
    func kitoScanIf<Content: View>(_ condition: Bool, _ transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
