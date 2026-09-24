//
//  KitoScanActions.swift
//  KitoScanner
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import Contacts
import ContactsUI
import EventKit
import EventKitUI
#if canImport(NetworkExtension)
import NetworkExtension
#endif

/// Joins Wi-Fi networks with `NEHotspotConfiguration` where the app can.
///
/// Joining needs the Hotspot Configuration capability. Without it (or in the Simulator) the
/// result card copies the password instead and tells the person where to paste it.
public enum KitoWiFiJoiner {
    public enum Outcome: Equatable, Sendable {
        case joined
        case cancelled
        /// Couldn't join; the message says why in plain words.
        case failed(String)
    }

    /// Whether this build can try to join networks at all.
    public static var isAvailable: Bool {
        #if canImport(NetworkExtension) && !targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    @MainActor
    public static func join(_ network: KitoWiFiNetwork) async -> Outcome {
        #if canImport(NetworkExtension) && !targetEnvironment(simulator)
        let configuration: NEHotspotConfiguration
        if let password = network.password, network.security != .open {
            configuration = NEHotspotConfiguration(ssid: network.ssid, passphrase: password, isWEP: network.security == .wep)
        } else {
            configuration = NEHotspotConfiguration(ssid: network.ssid)
        }
        configuration.hidden = network.isHidden
        configuration.joinOnce = false
        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
            return .joined
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain {
            switch NEHotspotConfigurationError(rawValue: error.code) {
            case .alreadyAssociated: return .joined
            case .userDenied: return .cancelled
            case .invalidWPAPassphrase, .invalidWEPPassphrase: return .failed("The password in this code looks wrong.")
            default: return .failed("This app can't join networks directly.")
            }
        } catch {
            return .failed("This app can't join networks directly.")
        }
        #else
        return .failed("Joining networks isn't available here.")
        #endif
    }
}

/// The system "New Contact" screen, filled in from a scanned card. Presenting it doesn't need
/// contacts permission.
struct KitoNewContactSheet: UIViewControllerRepresentable {
    let card: KitoContactCard
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: Self.contact(from: card))
        controller.contactStore = CNContactStore()
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    static func contact(from card: KitoContactCard) -> CNMutableContact {
        let contact = CNMutableContact()
        let words = card.name.split(separator: " ").map(String.init)
        if words.count > 1 {
            contact.givenName = words.dropLast().joined(separator: " ")
            contact.familyName = words.last ?? ""
        } else {
            contact.givenName = card.name
        }
        contact.organizationName = card.organization ?? ""
        contact.jobTitle = card.jobTitle ?? ""
        contact.phoneNumbers = card.phones.map { CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0)) }
        contact.emailAddresses = card.emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
        if let website = card.website { contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: website as NSString)] }
        if let address = card.address {
            let postal = CNMutablePostalAddress()
            postal.street = address
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal)]
        }
        return contact
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onDone()
        }
    }
}

/// The system event editor, filled in from a scanned event. On iOS 17 it runs without
/// calendar permission.
struct KitoEventEditSheet: UIViewControllerRepresentable {
    let event: KitoCalendarEvent
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let item = EKEvent(eventStore: store)
        item.title = event.title
        let start = event.start ?? Date()
        item.startDate = start
        item.endDate = event.end ?? start.addingTimeInterval(event.isAllDay ? 86_400 : 3_600)
        item.isAllDay = event.isAllDay
        item.location = event.location
        item.notes = event.notes
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = item
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
