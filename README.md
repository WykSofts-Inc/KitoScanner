# KitoScanner

Scanning for SwiftUI: live QR and barcode scanning, smart results for every kind of code, QR
generation, document scanning to PDF and on-device card reading. Part of the
[Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

Every view reads `@Environment(\.kitoTheme)`, takes an optional `tint`, works in light and dark,
respects Reduce Motion and is labelled for VoiceOver.

## Live scanning

```swift
KitoCodeScanner(overlay: .laser) { code in
    print(code.payload)          // .payment, .wifi, .url, .contact, .product …
}

KitoCodeScanner(
    symbologies: KitoSymbology.retail,   // EAN-13 / UPC-A, EAN-8, UPC-E; the window turns wide
    overlay: .frame,                     // .corners, .laser, .frame, .minimal
    mode: .continuous,                   // keeps going; scans collect in a recent-scans tray
    onPay: { request in checkout(request) },
    onScan: { code in cart.add(code) },
    onClose: { dismiss() }
)
```

- Uses VisionKit's `DataScannerViewController` when it's supported and available, otherwise an
  `AVCaptureMetadataOutput` scanner (`engine: .visionKit`, `.avFoundation` or `.photos` to choose).
- Torch, 1× / 2× / 3× zoom and pinch to zoom; a highlight around the code and a success haptic on
  every read.
- `.singleShot` (the default) stops on the first code and shows a result card with "Scan again";
  `.continuous` ignores the same code for a couple of seconds so it doesn't repeat.
- No camera (the Simulator) or access denied: pick a photo and the codes in it are found with
  Vision and highlighted, or tap **Use sample code** to cycle through sample payment, Wi-Fi,
  product, contact, link, event, place and SMS codes.

Add `NSCameraUsageDescription` to your Info.plist.

## What's in a code

`KitoScannedCode(raw:symbology:)` parses the raw string into a `KitoCodePayload`:

| Payload | Recognises |
| --- | --- |
| `.url` | `http(s)://…`, `www.…` |
| `.wifi` | `WIFI:S:…;T:WPA;P:…;H:true;;` (any field order, `\` escapes) |
| `.contact` | vCard 2.1–4.0 (`BEGIN:VCARD`, folded lines, parameters) and `MECARD:` |
| `.phone` | `tel:`, or a bare `+254…` number |
| `.email` | `mailto:` with subject and body, `MATMSG:`, or a bare address |
| `.sms` | `sms:` with `body=`, `SMSTO:number:message` |
| `.geo` | `geo:lat,lon[,alt]?q=…` |
| `.event` | `BEGIN:VEVENT` (inside a `VCALENDAR` or not), UTC, local and all-day dates |
| `.payment` | `kitopay://till/832910?amount=450&name=…`, `…/paybill/247247?account=…`, `…/phone/2547…` |
| `.product` | EAN-13, UPC-A, EAN-8, UPC-E and GTIN-14, with the check digit verified |
| `.text` | anything else |

The payload types also go the other way, so you can make codes to print:

```swift
KitoWiFiNetwork(ssid: "Kahawa House Guest", password: "karibu2026").payload
KitoPaymentRequest(kind: .till, number: "832910", amount: 450, merchant: "Mama Mboga Greens").payload
KitoContactCard(name: "Achieng Owuor", phones: ["+254 712 345 678"]).vCard
KitoGeoPoint(latitude: -1.28638, longitude: 36.81723, query: "Kenyatta Avenue").payload
```

## Result card

```swift
KitoScanResultCard(code: code, onPay: { request in checkout(request) })
```

Shows the right actions for each kind: open or share a link (with a warning for non-HTTPS),
join a Wi-Fi network or copy its password, add a contact, call, message, email, open a place in
Maps (with a map preview), add an event to the calendar, pay or copy a till / paybill number,
and look up a product (with its barcode redrawn and the check digit shown).

Joining Wi-Fi uses `NEHotspotConfiguration`, which needs the **Hotspot Configuration**
capability. Without it, or in the Simulator, the card copies the password and says where to
paste it. Adding a contact or event uses the system editors, which don't need contacts or
calendar permission.

## QR codes

```swift
KitoQRCodeView("https://wyksoftsinc.com")                                  // plain
KitoQRCodeView(payload, style: .dots)                                      // round dots, rounded eyes
KitoQRCodeView(payload, style: .rounded)
KitoQRCodeView(payload, style: .gradient([.teal, .indigo]), logo: Image("Mark"))   // logo → high correction

KitoQRCodeCard(KitoScannerSamples.payment.payload,
               title: "Mama Mboga Greens", subtitle: "Till 832910",
               caption: "Scan to pay")                                     // Share and Save buttons
```

Codes are generated with Core Image and drawn as vectors, always on a white quiet zone so they
scan in dark mode too. **Save** appears only when the app declares
`NSPhotoLibraryAddUsageDescription`. `KitoBarcodeView(ean13:)` draws EAN-13 barcodes.

## Documents

```swift
KitoDocumentScanner(title: "Receipt") { document in
    upload(document.pdfData())
}
```

The VisionKit document camera finds and straightens pages; then there's a crop-style preview, a
page strip (reorder or remove from the context menu), Colour / Greyscale / B&W filters and PDF
export. Where the document camera isn't supported it imports photos or sample pages instead.
Without UI: `KitoDocumentRenderer.apply(.blackAndWhite, to: page)` and
`KitoDocumentRenderer.pdfData(pages:)`.

## Cards

```swift
KitoCardScanner { details in
    form.last4 = details.last4          // "4242"
    form.expiry = details.expiry        // 08/29
    form.name = details.holderName      // "Achieng W Owuor"
}
```

Text is recognised on device with Vision. The number must pass the Luhn check; only the brand,
last four digits and a masked form (`•••• •••• •••• 4242`) are kept, and the photo is dropped as
soon as it's read. The parsing is available on its own:
`KitoCardTextParser.details(from: lines)`, `KitoCardExpiry.parse("VALID THRU 08/29")`,
`KitoCardMask.mask(number)`, `KitoCheckDigits.isValidLuhn(_:)`.

## Samples

`KitoScannerSamples` has sample payloads, photo-like code images, a test card and two document
pages, all drawn on device, for previews and the Simulator.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoScanner.git", from: "0.1.0")
```

## License

MIT — see [LICENSE](LICENSE).
