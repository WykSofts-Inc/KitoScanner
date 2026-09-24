//
//  KitoQRCodeView.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import Photos
import KitoCore

/// How a generated QR code is drawn.
public struct KitoQRStyle: Hashable, Sendable {
    public enum ModuleShape: String, Hashable, Sendable {
        /// Classic squares.
        case square
        /// Round dots.
        case dot
        /// Squares with softened corners.
        case rounded
    }

    public var moduleShape: ModuleShape
    /// Draws the three corner eyes as rounded squares instead of module by module.
    public var roundedEyes: Bool
    /// Two or more colours to sweep across the code, or nil for a solid colour.
    public var gradient: [Color]?

    public init(moduleShape: ModuleShape = .square, roundedEyes: Bool = false, gradient: [Color]? = nil) {
        self.moduleShape = moduleShape
        self.roundedEyes = roundedEyes
        self.gradient = gradient
    }

    /// Black squares on white: scans everywhere.
    public static let plain = KitoQRStyle()
    /// Round dots with rounded eyes.
    public static let dots = KitoQRStyle(moduleShape: .dot, roundedEyes: true)
    /// Softened squares with rounded eyes.
    public static let rounded = KitoQRStyle(moduleShape: .rounded, roundedEyes: true)

    /// Dots filled with a diagonal gradient. Keep the colours dark enough to contrast with white.
    public static func gradient(_ colors: [Color], moduleShape: ModuleShape = .dot) -> KitoQRStyle {
        KitoQRStyle(moduleShape: moduleShape, roundedEyes: true, gradient: colors)
    }
}

/// A QR code generated on device with Core Image and drawn crisply at any size, always on a
/// white quiet zone so it scans in dark mode too.
///
///     KitoQRCodeView("kitopay://till/832910?amount=450", style: .dots)
///     KitoQRCodeView(url, style: .gradient([.purple, .blue]), logo: Image("AppMark"))
public struct KitoQRCodeView: View {
    private let matrix: KitoQRMatrix?
    private let style: KitoQRStyle
    private let logo: Image?
    private let tint: Color?
    var animatesIn = true
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// - Parameters:
    ///   - content: The text to encode.
    ///   - style: Module shape, eyes and optional gradient.
    ///   - correction: Error correction. A logo raises it to `.high` automatically.
    ///   - logo: An image for the middle of the code.
    ///   - tint: The module colour when there's no gradient; black by default.
    public init(_ content: String, style: KitoQRStyle = .plain, correction: KitoQRCorrection = .medium, logo: Image? = nil, tint: Color? = nil) {
        self.matrix = KitoQRMatrix(content, correction: logo == nil ? correction : .high)
        self.style = style
        self.logo = logo
        self.tint = tint
    }

    /// A code from a matrix you already have.
    public init(matrix: KitoQRMatrix, style: KitoQRStyle = .plain, logo: Image? = nil, tint: Color? = nil) {
        self.matrix = matrix
        self.style = style
        self.logo = logo
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
            if let matrix {
                KitoQRCanvas(matrix: matrix, style: style, color: tint ?? .black, logoFraction: logo == nil ? 0 : Self.logoFraction)
                    .padding(quietPadding(for: matrix))
                    .opacity(isShown ? 1 : 0)
                    .scaleEffect(isShown ? 1 : 0.94)
                if let logo {
                    logoBadge(logo)
                }
            } else {
                Label("Too long for a QR code", systemImage: "exclamationmark.triangle.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
                    .padding()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.25)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("QR code")
        .accessibilityAddTraits(.isImage)
    }

    static let logoFraction = 0.24

    private var isShown: Bool { appeared || reduceMotion || !animatesIn }

    /// The same code without the entrance animation, for `ImageRenderer`.
    func withoutEntrance() -> KitoQRCodeView {
        var copy = self
        copy.animatesIn = false
        return copy
    }

    private func quietPadding(for matrix: KitoQRMatrix) -> CGFloat {
        // Roughly two modules at typical sizes; keeps the quiet zone scanners need.
        matrix.size > 40 ? 12 : 16
    }

    private func logoBadge(_ logo: Image) -> some View {
        GeometryReader { proxy in
            let side = proxy.size.width * Self.logoFraction * 0.86
            logo
                .resizable()
                .scaledToFit()
                .padding(side * 0.14)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: side * 0.26, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

/// Draws the modules.
struct KitoQRCanvas: View {
    let matrix: KitoQRMatrix
    let style: KitoQRStyle
    let color: Color
    var logoFraction: Double

    var body: some View {
        Canvas { context, size in
            let path = KitoQRPathBuilder(matrix: matrix, style: style, logoFraction: logoFraction).path(in: size)
            context.fill(path, with: shading(in: size))
        }
    }

    private func shading(in size: CGSize) -> GraphicsContext.Shading {
        guard let colors = style.gradient, colors.count > 1 else { return .color(color) }
        return .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height))
    }
}

/// Turns a matrix into one path, so gradients sweep across the whole code.
struct KitoQRPathBuilder {
    let matrix: KitoQRMatrix
    let style: KitoQRStyle
    var logoFraction: Double

    func path(in size: CGSize) -> Path {
        let side = min(size.width, size.height)
        let module = side / CGFloat(matrix.size)
        var path = Path()
        for row in 0..<matrix.size {
            for column in 0..<matrix.size where matrix[row, column] {
                if style.roundedEyes, matrix.isFinder(row: row, column: column) { continue }
                if matrix.isUnderLogo(row: row, column: column, fraction: logoFraction) { continue }
                addModule(&path, rect: CGRect(x: CGFloat(column) * module, y: CGFloat(row) * module, width: module, height: module))
            }
        }
        if style.roundedEyes {
            for origin in matrix.finderOrigins { addEye(&path, row: origin.row, column: origin.column, module: module) }
        }
        return path
    }

    private func addModule(_ path: inout Path, rect: CGRect) {
        switch style.moduleShape {
        case .square:
            // A hair of overlap hides seams between neighbours.
            path.addRect(rect.insetBy(dx: -0.25, dy: -0.25))
        case .dot:
            path.addEllipse(in: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06))
        case .rounded:
            let inset = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
            path.addRoundedRect(in: inset, cornerSize: CGSize(width: rect.width * 0.32, height: rect.height * 0.32))
        }
    }

    private func addEye(_ path: inout Path, row: Int, column: Int, module: CGFloat) {
        let outer = CGRect(x: CGFloat(column) * module, y: CGFloat(row) * module, width: module * 7, height: module * 7)
        let ring = outer.insetBy(dx: module, dy: module)
        let pupil = outer.insetBy(dx: module * 2, dy: module * 2)
        path.addRoundedRect(in: outer, cornerSize: CGSize(width: module * 2.2, height: module * 2.2), style: .continuous)
        // Drawn the other way round so the non-zero fill leaves the ring hollow.
        path.addPath(Path(roundedRect: ring, cornerSize: CGSize(width: module * 1.5, height: module * 1.5), style: .continuous).reversedForHole())
        path.addRoundedRect(in: pupil, cornerSize: CGSize(width: module * 1.1, height: module * 1.1), style: .continuous)
    }
}

extension Path {
    /// The same outline traced in the opposite direction, so a non-zero fill treats it as a hole.
    func reversedForHole() -> Path {
        let box = boundingRect
        let flip = CGAffineTransform(translationX: 0, y: box.midY * 2).scaledBy(x: 1, y: -1)
        // Mirroring vertically reverses the winding; the shape is symmetric so it lands in place.
        return applying(flip)
    }
}

/// A QR code on a card with a title, a caption such as "Scan to pay", and Share and Save
/// buttons. Save appears only when the app declares `NSPhotoLibraryAddUsageDescription`.
public struct KitoQRCodeCard: View {
    private let content: String
    private let title: String?
    private let subtitle: String?
    private let caption: String
    private let style: KitoQRStyle
    private let logo: Image?
    private let showsActions: Bool
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @State private var rendered: UIImage?
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable { case idle, saving, saved, failed }

    public init(_ content: String, title: String? = nil, subtitle: String? = nil, caption: String = "Scan to pay",
                style: KitoQRStyle = .dots, logo: Image? = nil, showsActions: Bool = true, tint: Color? = nil) {
        self.content = content
        self.title = title
        self.subtitle = subtitle
        self.caption = caption
        self.style = style
        self.logo = logo
        self.showsActions = showsActions
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: theme.spacing.md) {
            poster
            if showsActions { actions }
        }
        .task(id: content) { rendered = renderImage() }
    }

    private var accent: Color { theme.accent(tint) }

    private var poster: some View { makePoster(animated: true) }

    private func makePoster(animated: Bool) -> some View {
        VStack(spacing: theme.spacing.md) {
            if title != nil || subtitle != nil {
                VStack(spacing: 4) {
                    if let title {
                        Text(title).font(theme.typography.titleMedium.weight(.bold)).foregroundStyle(theme.colors.onSurface)
                    }
                    if let subtitle {
                        Text(subtitle).font(theme.typography.caption).foregroundStyle(theme.colors.onSurface.opacity(0.6))
                    }
                }
                .multilineTextAlignment(.center)
            }
            qrCode(animated: animated)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
                .overlay(bracketFrame)
                .frame(maxWidth: 260)
            Label(caption, systemImage: "qrcode.viewfinder")
                .font(theme.typography.label.weight(.semibold))
                .foregroundStyle(theme.colors.onPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(accent))
        }
        .padding(theme.spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                .fill(theme.colors.surface)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).stroke(theme.colors.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, subtitle, caption].compactMap { $0 }.joined(separator: ", ") + ", QR code")
    }

    @ViewBuilder
    private func qrCode(animated: Bool) -> some View {
        let code = KitoQRCodeView(content, style: style, logo: logo, tint: style.gradient == nil ? codeColor : nil)
        if animated { code } else { code.withoutEntrance() }
    }

    /// Accent brackets hugging the code.
    private var bracketFrame: some View {
        GeometryReader { proxy in
            KitoCornerBrackets(window: CGRect(origin: .zero, size: proxy.size).insetBy(dx: -6, dy: -6), radius: 22)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .accessibilityHidden(true)
    }

    /// Tints lighter than this don't scan reliably on white, so they fall back to black.
    private var codeColor: Color {
        guard let tint else { return .black }
        return KitoColorContrast.isDarkEnough(tint) ? tint : .black
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: theme.spacing.sm) {
            if let rendered {
                ShareLink(item: Image(uiImage: rendered), preview: SharePreview(title ?? caption, image: Image(uiImage: rendered))) {
                    KitoScanActionLabel(title: "Share", systemImage: "square.and.arrow.up", prominent: true, accent: accent)
                }
                .buttonStyle(KitoScanPressStyle())
            }
            if Self.canSaveToPhotos {
                Button { save() } label: {
                    KitoScanActionLabel(title: saveTitle, systemImage: saveSymbol, accent: accent)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(KitoScanPressStyle())
                .disabled(rendered == nil || saveState == .saving)
                .sensoryFeedback(.success, trigger: saveState == .saved)
            }
            ShareLink(item: content) {
                KitoScanActionLabel(title: "Share text", systemImage: "text.quote", accent: accent)
            }
            .buttonStyle(KitoScanPressStyle())
        }
    }

    private var saveTitle: String {
        switch saveState {
        case .idle, .saving: return "Save"
        case .saved: return "Saved"
        case .failed: return "Not saved"
        }
    }

    private var saveSymbol: String {
        switch saveState {
        case .idle, .saving: return "square.and.arrow.down"
        case .saved: return "checkmark"
        case .failed: return "xmark"
        }
    }

    static var canSaveToPhotos: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil
    }

    @MainActor
    private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(content: makePoster(animated: false).frame(width: 360).padding(20).background(theme.colors.background).environment(\.kitoTheme, theme))
        renderer.scale = max(displayScale, 2)
        return renderer.uiImage
    }

    private func save() {
        guard let rendered else { return }
        saveState = .saving
        Task { @MainActor in
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { saveState = .failed; return }
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: rendered) }
                saveState = .saved
            } catch {
                saveState = .failed
            }
            try? await Task.sleep(for: .seconds(2))
            saveState = .idle
        }
    }
}

enum KitoColorContrast {
    /// True when the colour is dark enough (relative luminance ≤ 0.45) to read on white.
    static func isDarkEnough(_ color: Color) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return true }
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance <= 0.45
    }
}

/// An EAN-13 barcode drawn from its digits, with the human-readable numbers underneath.
///
///     KitoBarcodeView(ean13: "6161001234567")
public struct KitoBarcodeView: View {
    private let digits: String
    private let modules: [Bool]?
    private let showsDigits: Bool
    private let tint: Color?

    /// A 13-digit EAN (or a 12-digit body, which gets its check digit).
    public init(ean13 code: String, showsDigits: Bool = true, tint: Color? = nil) {
        let full = code.count == 12 ? (KitoCheckDigits.appendingGTINCheckDigit(to: code) ?? code) : code
        self.digits = full
        self.modules = KitoEAN13.modules(for: full)
        self.showsDigits = showsDigits
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            guard let modules else { return }
            draw(modules, in: &context, size: size)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Barcode \(digits.map(String.init).joined(separator: " "))")
        .accessibilityAddTraits(.isImage)
    }

    private func draw(_ modules: [Bool], in context: inout GraphicsContext, size: CGSize) {
        let module = size.width / 104
        let origin = module * 8
        let textHeight = showsDigits ? module * 9 : 0
        let barHeight = size.height - textHeight
        var bars = Path()
        var guards = Path()
        for (index, isBar) in modules.enumerated() where isBar {
            let x = origin + CGFloat(index) * module
            if KitoEAN13.isGuard(index) {
                guards.addRect(CGRect(x: x, y: 0, width: module, height: barHeight + textHeight * 0.55))
            } else {
                bars.addRect(CGRect(x: x, y: 0, width: module, height: barHeight))
            }
        }
        let ink = tint ?? .black
        context.fill(bars, with: .color(ink))
        context.fill(guards, with: .color(ink))
        guard showsDigits, digits.count == 13 else { return }
        drawDigits(in: &context, module: module, origin: origin, baseline: barHeight + textHeight * 0.55, ink: ink)
    }

    private func drawDigits(in context: inout GraphicsContext, module: CGFloat, origin: CGFloat, baseline: CGFloat, ink: Color) {
        let font = Font.system(size: module * 8, weight: .medium, design: .monospaced)
        let characters = Array(digits)
        context.draw(Text(String(characters[0])).font(font).foregroundStyle(ink), at: CGPoint(x: origin - module * 4, y: baseline))
        context.draw(Text(String(characters[1...6])).font(font).foregroundStyle(ink), at: CGPoint(x: origin + module * 24, y: baseline))
        context.draw(Text(String(characters[7...12])).font(font).foregroundStyle(ink), at: CGPoint(x: origin + module * 71, y: baseline))
    }
}
