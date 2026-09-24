//
//  KitoDocumentScanner.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import PDFKit
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
@preconcurrency import VisionKit
import KitoCore

/// The look applied to scanned pages.
public enum KitoDocumentFilter: String, CaseIterable, Hashable, Sendable {
    /// Colour, with lighting evened out a little.
    case colour
    /// Greyscale with a touch more contrast.
    case greyscale
    /// Crisp black text on white paper, like a photocopy.
    case blackAndWhite

    public var title: String {
        switch self {
        case .colour: return "Colour"
        case .greyscale: return "Greyscale"
        case .blackAndWhite: return "B&W"
        }
    }

    public var systemImage: String {
        switch self {
        case .colour: return "paintpalette.fill"
        case .greyscale: return "circle.lefthalf.filled"
        case .blackAndWhite: return "doc.plaintext.fill"
        }
    }
}

/// Filters pages and builds PDFs, on device.
public enum KitoDocumentRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Applies a document filter with Core Image.
    public static func apply(_ filter: KitoDocumentFilter, to image: UIImage) -> UIImage {
        guard let cgImage = KitoImageTools.uprightCGImage(image) else { return image }
        let input = CIImage(cgImage: cgImage)
        let output = filtered(input, filter)
        guard let rendered = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }

    static func filtered(_ input: CIImage, _ filter: KitoDocumentFilter) -> CIImage {
        let enhancer = CIFilter.documentEnhancer()
        enhancer.inputImage = input
        let controls = CIFilter.colorControls()
        switch filter {
        case .colour:
            enhancer.amount = 0.6
            controls.inputImage = enhancer.outputImage ?? input
            controls.saturation = 1.08
            controls.contrast = 1.06
            controls.brightness = 0.01
        case .greyscale:
            enhancer.amount = 0.8
            controls.inputImage = enhancer.outputImage ?? input
            controls.saturation = 0
            controls.contrast = 1.18
            controls.brightness = 0.02
        case .blackAndWhite:
            enhancer.amount = 1
            controls.inputImage = enhancer.outputImage ?? input
            controls.saturation = 0
            controls.contrast = 2.6
            controls.brightness = 0.16
        }
        return (controls.outputImage ?? input).cropped(to: input.extent)
    }

    /// One PDF page per image, each fitted to an A4 page.
    public static func pdfData(pages: [UIImage]) -> Data {
        let document = PDFDocument()
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        for (index, image) in pages.enumerated() {
            let box = image.size.width > image.size.height ? CGRect(x: 0, y: 0, width: a4.height, height: a4.width) : a4
            let options: [PDFPage.ImageInitializationOption: Any] = [.mediaBox: box, .compressionQuality: 0.82, .upscaleIfSmaller: true]
            if let page = PDFPage(image: image, options: options) {
                document.insert(page, at: index)
            }
        }
        return document.dataRepresentation() ?? Data()
    }

    /// Writes the PDF to a temporary file named after `title`, ready to share.
    public static func writePDF(pages: [UIImage], title: String) throws -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe.isEmpty ? "Scan" : safe).appendingPathExtension("pdf")
        try pdfData(pages: pages).write(to: url, options: .atomic)
        return url
    }
}

/// Pages from a document scan, with the filter the person picked already applied.
public struct KitoScannedDocument: @unchecked Sendable {
    public let pages: [UIImage]
    public let filter: KitoDocumentFilter

    public init(pages: [UIImage], filter: KitoDocumentFilter) {
        self.pages = pages
        self.filter = filter
    }

    public func pdfData() -> Data { KitoDocumentRenderer.pdfData(pages: pages) }
}

/// VisionKit's document camera. It finds page edges, straightens them and returns the pages.
/// Check `isSupported` first; it's unavailable in the Simulator.
public struct KitoDocumentCamera: UIViewControllerRepresentable {
    private let onFinish: ([UIImage]) -> Void
    private let onCancel: () -> Void

    public init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void = {}) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    @MainActor
    public static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    public func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}

/// Scan, review and export documents: the VisionKit document camera, a page strip to reorder or
/// remove pages, Colour / Greyscale / B&W filters and PDF export. Where the document camera
/// isn't available it imports photos or sample pages instead.
public struct KitoDocumentScanner: View {
    private let title: String
    private let tint: Color?
    private let onFinish: ((KitoScannedDocument) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var originals: [UIImage]
    @State private var filtered: [UIImage] = []
    @State private var filter: KitoDocumentFilter = .colour
    @State private var selection = 0
    @State private var showsCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isRendering = false
    @State private var shareItem: KitoShareItem?
    @State private var revision = 0
    @State private var message: String?

    /// - Parameters:
    ///   - title: Used for the PDF's file name.
    ///   - pages: Pages to start with, e.g. `KitoScannerSamples.documentPages()`.
    ///   - tint: Accent colour; the theme's primary by default.
    ///   - onFinish: Shows a Done button that hands back the filtered pages.
    public init(title: String = "Scan", pages: [UIImage] = [], tint: Color? = nil, onFinish: ((KitoScannedDocument) -> Void)? = nil) {
        self.title = title
        self.tint = tint
        self.onFinish = onFinish
        _originals = State(initialValue: pages)
    }

    private var accent: Color { theme.accent(tint) }

    public var body: some View {
        VStack(spacing: theme.spacing.md) {
            if originals.isEmpty {
                emptyState
            } else {
                preview
                filterPicker
                pageStrip
                exportBar
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
        .task(id: renderKey) { await render() }
        .fullScreenCover(isPresented: $showsCamera) {
            KitoDocumentCamera(onFinish: { pages in
                showsCamera = false
                add(pages)
            }, onCancel: { showsCamera = false })
            .ignoresSafeArea()
        }
        .sheet(item: $shareItem) { item in
            KitoActivitySheet(items: [item.url]).ignoresSafeArea().presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2), value: originals.count)
    }

    private var renderKey: String { "\(filter.rawValue)-\(revision)" }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: theme.spacing.lg) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.colors.surface)
                    .frame(width: 150, height: 200)
                    .rotationEffect(.degrees(-8))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.colors.surface)
                    .overlay(alignment: .topLeading) { KitoFakeLines(color: theme.colors.onSurface.opacity(0.15)).padding(22) }
                    .frame(width: 150, height: 200)
                    .rotationEffect(.degrees(5))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                KitoCornerBrackets(window: CGRect(x: 0, y: 0, width: 190, height: 240), radius: 22)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 190, height: 240)
            }
            .accessibilityHidden(true)
            VStack(spacing: theme.spacing.xs) {
                Text("Scan a document").font(theme.typography.titleLarge.weight(.bold)).foregroundStyle(theme.colors.onBackground)
                Text(KitoDocumentCamera.isSupported
                     ? "Edges are found and straightened for you. Review, pick a filter, then export a PDF."
                     : "The document camera isn't available on this device. Import photos of pages, or try the samples.")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.onBackground.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            addButtons(prominent: true)
            Spacer()
        }
        .padding(.horizontal, theme.spacing.md)
    }

    private func addButtons(prominent: Bool) -> some View {
        let cameraSupported = KitoDocumentCamera.isSupported
        return VStack(spacing: theme.spacing.xs) {
            if cameraSupported {
                Button { showsCamera = true } label: {
                    KitoScanActionLabel(title: "Scan pages", systemImage: "doc.viewfinder", prominent: prominent, accent: accent).frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
            }
            HStack(spacing: theme.spacing.xs) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    KitoScanActionLabel(title: "Import photos", systemImage: "photo.on.rectangle",
                                        prominent: prominent && !cameraSupported, accent: accent).frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
                Button { add(KitoScannerSamples.documentPages()) } label: {
                    KitoScanActionLabel(title: "Sample pages", systemImage: "wand.and.stars", accent: accent).frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
            }
        }
        .frame(maxWidth: 380)
    }

    // MARK: Review

    private var currentPage: UIImage? {
        let pages = filtered.count == originals.count ? filtered : originals
        return pages.indices.contains(selection) ? pages[selection] : pages.first
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
            if let page = currentPage {
                KitoCropPreview(image: page, accent: accent)
                    .padding(26)
                    .id(selection)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
            }
            if isRendering {
                ProgressView().tint(.white).padding(10).background(Circle().fill(.ultraThinMaterial))
            }
            VStack {
                HStack {
                    Spacer()
                    Text("Page \(min(selection + 1, originals.count)) of \(originals.count)")
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.45)))
                        .contentTransition(.numericText())
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: selection)
    }

    private var filterPicker: some View {
        HStack(spacing: theme.spacing.xs) {
            ForEach(KitoDocumentFilter.allCases, id: \.self) { option in
                Button { filter = option } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .font(theme.typography.label.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(filter == option ? theme.colors.onPrimary : theme.colors.onSurface)
                        .background(Capsule().fill(filter == option ? accent : theme.colors.surfaceMuted))
                }
                .buttonStyle(KitoScanPressStyle())
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3), value: filter)
    }

    private var pageStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.sm) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, page in
                        thumbnail(page, index: index).id(index)
                    }
                    addTile
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .onChange(of: selection) { _, value in
                withAnimation(reduceMotion ? nil : .snappy) { reader.scrollTo(value, anchor: .center) }
            }
        }
        .frame(height: 104)
    }

    private var thumbnails: [UIImage] { filtered.count == originals.count ? filtered : originals }

    private func thumbnail(_ page: UIImage, index: Int) -> some View {
        let isSelected = index == selection
        return Button { selection = index } label: {
            Image(uiImage: page)
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isSelected ? accent : theme.colors.border, lineWidth: isSelected ? 3 : 1))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isSelected ? accent : Color.black.opacity(0.55)))
                        .offset(x: 5, y: 5)
                }
                .scaleEffect(isSelected && !reduceMotion ? 1.05 : 1)
        }
        .buttonStyle(KitoScanPressStyle())
        .contextMenu {
            Button { move(index, by: -1) } label: { Label("Move earlier", systemImage: "arrow.backward") }.disabled(index == 0)
            Button { move(index, by: 1) } label: { Label("Move later", systemImage: "arrow.forward") }.disabled(index == originals.count - 1)
            Button(role: .destructive) { remove(index) } label: { Label("Remove page", systemImage: "trash") }
        }
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            Button("Move earlier") { move(index, by: -1) }
            Button("Move later") { move(index, by: 1) }
            Button("Remove page") { remove(index) }
        }
    }

    private var addTile: some View {
        Menu {
            if KitoDocumentCamera.isSupported {
                Button { showsCamera = true } label: { Label("Scan more pages", systemImage: "doc.viewfinder") }
            }
            Button { add(KitoScannerSamples.documentPages()) } label: { Label("Add sample pages", systemImage: "wand.and.stars") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 66, height: 88)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.colors.surfaceMuted))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(accent.opacity(0.6)))
        }
        .accessibilityLabel("Add pages")
    }

    private var exportBar: some View {
        VStack(spacing: theme.spacing.xs) {
            if let message {
                Text(message).font(theme.typography.caption).foregroundStyle(theme.colors.danger)
            }
            HStack(spacing: theme.spacing.xs) {
                Button { exportPDF() } label: {
                    KitoScanActionLabel(title: "Export PDF", systemImage: "doc.richtext", prominent: onFinish == nil, accent: accent).frame(maxWidth: .infinity)
                }
                .buttonStyle(KitoScanPressStyle())
                .disabled(isRendering)
                if let onFinish {
                    Button { onFinish(KitoScannedDocument(pages: thumbnails, filter: filter)) } label: {
                        KitoScanActionLabel(title: "Done", systemImage: "checkmark", prominent: true, accent: accent).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KitoScanPressStyle())
                    .disabled(isRendering)
                }
            }
        }
    }

    // MARK: Work

    private func add(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        let start = originals.count
        originals.append(contentsOf: pages.map { KitoImageTools.downscaled($0, maxDimension: 2_200) })
        revision += 1
        selection = start
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard originals.indices.contains(index), originals.indices.contains(target) else { return }
        originals.swapAt(index, target)
        if filtered.indices.contains(index), filtered.indices.contains(target) { filtered.swapAt(index, target) }
        revision += 1
        selection = target
    }

    private func remove(_ index: Int) {
        guard originals.indices.contains(index) else { return }
        originals.remove(at: index)
        if filtered.indices.contains(index) { filtered.remove(at: index) }
        revision += 1
        selection = min(selection, max(originals.count - 1, 0))
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
        }
        pickerItems = []
        if images.isEmpty { message = "Those photos couldn't be opened." } else { message = nil; add(images) }
    }

    private func render() async {
        let pages = originals
        let chosen = filter
        guard !pages.isEmpty else { filtered = []; return }
        isRendering = true
        let output = await Task.detached(priority: .userInitiated) {
            pages.map { KitoDocumentRenderer.apply(chosen, to: $0) }
        }.value
        guard !Task.isCancelled else { return }
        isRendering = false
        if pages.count == originals.count { filtered = output }
    }

    private func exportPDF() {
        let pages = thumbnails
        let name = title
        Task { @MainActor in
            isRendering = true
            let url = await Task.detached(priority: .userInitiated) { try? KitoDocumentRenderer.writePDF(pages: pages, title: name) }.value
            isRendering = false
            if let url { shareItem = KitoShareItem(url: url) } else { message = "The PDF couldn't be written." }
        }
    }
}

/// A page on a dark stage with crop handles and edge guides, the way a scanner shows its crop.
struct KitoCropPreview: View {
    let image: UIImage
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        GeometryReader { proxy in
            let frame = KitoScanGeometry.aspectFitRect(content: image.size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                    .position(x: frame.midX, y: frame.midY)
                Rectangle()
                    .stroke(accent.opacity(0.9), lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                ForEach(0..<4, id: \.self) { corner in
                    handle.position(handlePoint(corner, in: frame))
                }
            }
            .rotation3DEffect(.degrees(settled || reduceMotion ? 0 : 8), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .scaleEffect(settled || reduceMotion ? 1 : 0.94)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.25)) { settled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanned page")
        .accessibilityAddTraits(.isImage)
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(accent, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 3)
    }

    private func handlePoint(_ corner: Int, in frame: CGRect) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: frame.minX, y: frame.minY)
        case 1: return CGPoint(x: frame.maxX, y: frame.minY)
        case 2: return CGPoint(x: frame.maxX, y: frame.maxY)
        default: return CGPoint(x: frame.minX, y: frame.maxY)
        }
    }
}

/// Grey bars suggesting lines of text.
struct KitoFakeLines: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Capsule().fill(color).frame(width: 70, height: 8)
            ForEach([96.0, 84, 100, 60, 90, 72], id: \.self) { width in
                Capsule().fill(color.opacity(0.7)).frame(width: width, height: 5)
            }
        }
    }
}

/// The system share sheet.
struct KitoActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file to hand to the share sheet.
struct KitoShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
