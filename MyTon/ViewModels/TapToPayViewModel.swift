//
//  TapToPayViewModel.swift
//  MyTon
//
//  Drives the Tap to Pay screen: connection token -> payment intent ->
//  capture -> receipt, with error handling.
//

import Foundation
import Combine

@MainActor
final class TapToPayViewModel: ObservableObject {

    // MARK: - Inputs
    @Published var amountText: String = "25.00"
    @Published var currency: String = "usd"
    /// Toggle to exercise the failure/error UI against the mock backend.
    @Published var simulateFailure: Bool = false

    // MARK: - Outputs
    @Published private(set) var statusMessage: String = "Ready to take a payment."
    @Published private(set) var isProcessing: Bool = false
    @Published var receipt: ReceiptData?
    @Published var errorMessage: String?
    @Published var showReceipt: Bool = false

    private let api = APIClient.shared

    /// Amount entered by the user converted to the smallest unit (cents).
    private var amountInCents: Int? {
        guard let value = Double(amountText.trimmingCharacters(in: .whitespaces)), value > 0 else {
            return nil
        }
        return Int((value * 100).rounded())
    }

    // MARK: - Flow

    /// Full Tap to Pay flow triggered by the button.
    func startPayment() async {
        errorMessage = nil
        receipt = nil

        guard let amount = amountInCents else {
            errorMessage = "Please enter a valid amount greater than 0."
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // 1. Bootstrap Stripe Terminal / Tap to Pay with a connection token.
            statusMessage = "Connecting reader…"
            _ = try await api.fetchConnectionToken()

            // 2. Create the payment intent on the backend.
            statusMessage = "Creating payment…"
            let intent = try await api.createPaymentIntent(amount: amount, currency: currency)

            // 3. Collect the tap. On a real device this is where the
            //    StripeTerminal reader collects the card. Here we hand the
            //    intent to the backend to finalize the charge.
            statusMessage = "Hold card near phone… tap to pay"
            let receipt = try await api.capturePayment(
                paymentIntentId: intent.id,
                simulateFailure: simulateFailure
            )

            // 4. Show the receipt.
            self.receipt = receipt
            self.showReceipt = true
            statusMessage = "Payment successful."
        } catch let error as APIError {
            // Declined card / validation / not-found -> show server message.
            errorMessage = error.message
            statusMessage = "Payment failed."
        } catch {
            errorMessage = "Something went wrong: \(error.localizedDescription)"
            statusMessage = "Payment failed."
        }
    }

    func reset() {
        receipt = nil
        errorMessage = nil
        showReceipt = false
        statusMessage = "Ready to take a payment."
    }
}
