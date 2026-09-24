# ``KitoScanner``

Live QR and barcode scanning, parsed results, QR generation, document scanning and card reading for SwiftUI.

## Overview

KitoScanner turns the camera into a scanner for QR codes and barcodes. ``KitoCodeScanner``
uses VisionKit's data scanner where it is supported and AVFoundation otherwise; without a
camera (the Simulator) or camera access it finds codes in photos with Vision, and offers
sample codes so the flow can always be tried. Add `NSCameraUsageDescription` to your
Info.plist.

```swift
KitoCodeScanner(
    symbologies: KitoSymbology.retail,
    overlay: .frame,
    mode: .continuous,
    onPay: { request in checkout(request) },
    onScan: { code in cart.add(code) },
    onClose: { dismiss() }
)
```

Every scan is a ``KitoScannedCode`` whose raw string is parsed into a ``KitoCodePayload``:
links, Wi-Fi networks, vCard and MECARD contacts, phone numbers, email, SMS, geo points,
calendar events, payment requests and retail product codes with verified check digits.
``KitoScanResultCard`` shows the right actions for each kind. The payload types also work the
other way, producing strings you can render with ``KitoQRCodeView`` or ``KitoQRCodeCard``.

``KitoDocumentScanner`` captures, straightens and filters pages and exports them to PDF.
``KitoCardScanner`` reads a payment card on device, keeps only the brand, last four digits,
expiry and holder name, and drops the photo as soon as it is read.

Every view reads the Kito theme from the environment, takes an optional `tint`, works in light
and dark, respects Reduce Motion and is labelled for VoiceOver.

## Topics

### Essentials

- ``KitoCodeScanner``
- ``KitoSymbology``
- ``KitoScanOverlayStyle``
- ``KitoScanMode``
- ``KitoScannerEngine``

### Scanned Codes

- ``KitoScannedCode``
- ``KitoCodePayload``
- ``KitoPayloadKind``
- ``KitoScanResultCard``
- ``KitoCodeParser``
- ``KitoWiFiNetwork``
- ``KitoContactCard``
- ``KitoEmailMessage``
- ``KitoTextMessage``
- ``KitoGeoPoint``
- ``KitoScannedEvent``
- ``KitoPaymentRequest``
- ``KitoProductCode``
- ``KitoWiFiJoiner``

### QR Codes and Barcodes

- ``KitoQRCodeView``
- ``KitoQRCodeCard``
- ``KitoQRStyle``
- ``KitoQRCorrection``
- ``KitoQRMatrix``
- ``KitoBarcodeView``
- ``KitoEAN13``

### Documents

- ``KitoDocumentScanner``
- ``KitoDocumentCamera``
- ``KitoScannedDocument``
- ``KitoDocumentFilter``
- ``KitoDocumentRenderer``

### Cards

- ``KitoCardScanner``
- ``KitoCardDetails``
- ``KitoScannedCardBrand``
- ``KitoCardExpiry``
- ``KitoCardMask``
- ``KitoCardTextParser``
- ``KitoCheckDigits``

### Detection and Samples

- ``KitoCodeDetector``
- ``KitoDetectedCode``
- ``KitoTextRecognizer``
- ``KitoScanGeometry``
- ``KitoScanThrottle``
- ``KitoRecentScans``
- ``KitoScannerSamples``
