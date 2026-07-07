//
//  TerminalManager.swift
//  MyTon
//
//  Real Stripe Terminal "Tap to Pay on iPhone" flow:
//  set token provider -> discover reader -> connect -> retrieve intent ->
//  collectPaymentMethod (this is what WAITS for the physical card tap) ->
//  confirmPaymentIntent -> build a receipt from the tapped card.
//
//  Requires (for a real physical tap):
//    • physical iPhone XS+ on iOS 16.7+
//    • the Tap to Pay entitlement on the App ID
//    • a real Stripe sk_ secret key on the backend
//  For testing without those, use `simulated: true` (Stripe's simulated reader).
//

import Foundation
import Combine
import StripeTerminal

final class TerminalManager: NSObject, ObservableObject {

    static let shared = TerminalManager()

    /// Human-readable reader/flow status for the UI.
    @Published var readerStatus: String = "Reader not connected"

    private var connectedReader: Reader?
    private var discoverCancelable: Cancelable?
    private var collectCancelable: Cancelable?
    private var discoverContinuation: CheckedContinuation<Reader, Error>?

    private override init() { super.init() }

    // MARK: - Public entry point

    /// Ensures a Tap to Pay reader is connected, then collects + confirms the
    /// payment for `clientSecret`. Returns a receipt built from the tapped card.
    func runPayment(clientSecret: String, simulated: Bool, locationId: String) async throws -> ReceiptData {
        try await ensureConnected(simulated: simulated, locationId: locationId)

        setStatus("Retrieving payment…")
        print("🟣 [Terminal] retrievePaymentIntent clientSecret=\(clientSecret.prefix(18))…")
        let intent = try await retrieve(clientSecret: clientSecret)

        setStatus("Waiting for card tap…")
        print("🟣 [Terminal] collectPaymentMethod — WAITING FOR REAL CARD TAP")
        let collected = try await collect(intent: intent)

        setStatus("Confirming payment…")
        print("🟣 [Terminal] confirmPaymentIntent…")
        let confirmed = try await confirm(intent: collected)

        setStatus("Payment complete")
        print("🟢 [Terminal] confirmed status=\(Self.statusString(confirmed.status))")
        return receipt(from: confirmed)
    }

    // MARK: - Connection

    private func ensureConnected(simulated: Bool, locationId: String) async throws {
        if !Terminal.hasTokenProvider() {
            Terminal.setTokenProvider(StripeConnectionTokenProvider())
            print("🟣 [Terminal] token provider set.")
        }
        if connectedReader != nil {
            print("🟣 [Terminal] reader already connected — reusing.")
            return
        }

        setStatus(simulated ? "Discovering simulated reader…" : "Discovering Tap to Pay reader…")
        print("🟣 [Terminal] discoverReaders simulated=\(simulated)")
        let reader = try await discover(simulated: simulated)

        setStatus("Connecting reader…")
        print("🟣 [Terminal] connectReader locationId=\(locationId)")
        let reader2 = try await connect(reader: reader, locationId: locationId)
        connectedReader = reader2
        setStatus("Reader connected")
    }

    private func discover(simulated: Bool) async throws -> Reader {
        let config = try TapToPayDiscoveryConfigurationBuilder()
            .setSimulated(simulated)
            .build()
        return try await withCheckedThrowingContinuation { cont in
            self.discoverContinuation = cont
            self.discoverCancelable = Terminal.shared.discoverReaders(config, delegate: self) { error in
                // Fires when discovery ends. Only surface an error if we never
                // delivered a reader through the delegate.
                if let error = error, let pending = self.discoverContinuation {
                    self.discoverContinuation = nil
                    pending.resume(throwing: error)
                }
            }
        }
    }

    private func connect(reader: Reader, locationId: String) async throws -> Reader {
        let config = try TapToPayConnectionConfigurationBuilder(delegate: self, locationId: locationId)
            .build()
        return try await withCheckedThrowingContinuation { cont in
            Terminal.shared.connectReader(reader, connectionConfig: config) { reader, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let reader = reader {
                    cont.resume(returning: reader)
                } else {
                    cont.resume(throwing: APIError(message: "Failed to connect the reader."))
                }
            }
        }
    }

    // MARK: - Payment steps

    private func retrieve(clientSecret: String) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { cont in
            Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { intent, error in
                if let error = error { cont.resume(throwing: error) }
                else if let intent = intent { cont.resume(returning: intent) }
                else { cont.resume(throwing: APIError(message: "Could not retrieve the payment.")) }
            }
        }
    }

    private func collect(intent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { cont in
            self.collectCancelable = Terminal.shared.collectPaymentMethod(intent) { intent, error in
                if let error = error { cont.resume(throwing: error) }
                else if let intent = intent { cont.resume(returning: intent) }
                else { cont.resume(throwing: APIError(message: "Could not read the card.")) }
            }
        }
    }

    private func confirm(intent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { cont in
            Terminal.shared.confirmPaymentIntent(intent) { intent, error in
                if let error = error {
                    // A declined card surfaces here.
                    cont.resume(throwing: APIError(message: error.localizedDescription))
                } else if let intent = intent {
                    cont.resume(returning: intent)
                } else {
                    cont.resume(throwing: APIError(message: "The payment could not be confirmed."))
                }
            }
        }
    }

    // MARK: - Receipt

    private func receipt(from intent: PaymentIntent) -> ReceiptData {
        let cardPresent = intent.charges.first?.paymentMethodDetails?.cardPresent
        let brand = cardPresent.map { Self.brandString($0.brand) } ?? "Card"
        let last4 = cardPresent?.last4 ?? "----"
        let amount = Int(intent.amount)
        let amountDisplay = "\(intent.currency.uppercased()) \(String(format: "%.2f", Double(amount) / 100.0))"
        return ReceiptData(
            receiptId: intent.stripeId ?? "rcpt_local",
            paymentIntentId: intent.stripeId ?? "pi_local",
            merchant: "eventFun",
            amount: amount,
            currency: intent.currency,
            amountDisplay: amountDisplay,
            status: Self.statusString(intent.status),
            cardBrand: brand,
            cardLast4: last4,
            date: ISO8601DateFormatter().string(from: intent.created)
        )
    }

    // MARK: - Helpers

    private func setStatus(_ message: String) {
        DispatchQueue.main.async { self.readerStatus = message }
    }

    private static func brandString(_ brand: CardBrand) -> String {
        switch brand {
        case .visa: return "Visa"
        case .amex: return "American Express"
        case .masterCard: return "Mastercard"
        case .discover: return "Discover"
        case .JCB: return "JCB"
        case .dinersClub: return "Diners Club"
        case .interac: return "Interac"
        default: return "Card"
        }
    }

    private static func statusString(_ status: PaymentIntentStatus) -> String {
        switch status {
        case .succeeded: return "succeeded"
        case .requiresPaymentMethod: return "requires_payment_method"
        case .requiresConfirmation: return "requires_confirmation"
        case .requiresCapture: return "requires_capture"
        case .processing: return "processing"
        case .canceled: return "canceled"
        default: return "unknown"
        }
    }
}

// MARK: - Stripe delegates

extension TerminalManager: DiscoveryDelegate {
    func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        guard let reader = readers.first, let cont = discoverContinuation else { return }
        discoverContinuation = nil
        print("🟣 [Terminal] discovered reader: \(reader.serialNumber ?? "unknown")")
        cont.resume(returning: reader)
    }
}

extension TerminalManager: TapToPayReaderDelegate {
    func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        setStatus("Installing reader update…")
    }

    func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        setStatus("Updating reader… \(Int(progress * 100))%")
    }

    func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        if let error = error {
            setStatus("Reader update failed: \(error.localizedDescription)")
        }
    }

    func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {
        setStatus(Terminal.stringFromReaderInputOptions(inputOptions))
    }

    func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
        setStatus(Terminal.stringFromReaderDisplayMessage(displayMessage))
    }
}
