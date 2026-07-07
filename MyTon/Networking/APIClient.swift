//
//  APIClient.swift
//  MyTon
//
//  Reusable networking helper. All endpoints are public (no auth token).
//  The generic `post` function is shared by every API call.
//

import Foundation

final class APIClient {

    /// Shared singleton so view models reuse the same helper.
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Generic request

    /// Sends a POST request with a JSON body and decodes `data` as `T`.
    /// - Reads the `success` flag first; if the server reports failure it
    ///   throws an `APIError` carrying the server `message`.
    func post<T: Decodable>(
        path: String,
        body: [String: Any] = [:],
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid server response.")
        }

        // Read success / message first so failures (e.g. declined card,
        // 400/402/404) surface a clean message instead of a decode error.
        let status = try decoder.decode(APIStatus.self, from: data)
        guard status.success else {
            throw APIError(message: status.message)
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError(message: status.message)
        }

        let wrapper = try decoder.decode(APIResponse<T>.self, from: data)
        guard let payload = wrapper.data else {
            throw APIError(message: "Missing data in server response.")
        }
        return payload
    }

    // MARK: - Endpoints

    /// POST /connection_token — used to bootstrap Stripe Terminal / Tap to Pay.
    func fetchConnectionToken() async throws -> ConnectionTokenData {
        try await post(path: APIConfig.Path.connectionToken, as: ConnectionTokenData.self)
    }

    /// POST /create_payment_intent — amount is in the smallest unit (cents).
    func createPaymentIntent(amount: Int, currency: String = "usd") async throws -> PaymentIntentData {
        try await post(
            path: APIConfig.Path.createPaymentIntent,
            body: ["amount": amount, "currency": currency],
            as: PaymentIntentData.self
        )
    }

    /// POST /capture_payment — finalizes the charge after the card is tapped.
    /// Throws `APIError` with the decline message when the payment fails.
    func capturePayment(paymentIntentId: String, simulateFailure: Bool = false) async throws -> ReceiptData {
        try await post(
            path: APIConfig.Path.capturePayment,
            body: ["payment_intent_id": paymentIntentId, "simulate_failure": simulateFailure],
            as: ReceiptData.self
        )
    }

    /// POST /receipt — fetches the receipt for a completed payment.
    func fetchReceipt(paymentIntentId: String) async throws -> ReceiptData {
        try await post(
            path: APIConfig.Path.receipt,
            body: ["payment_intent_id": paymentIntentId],
            as: ReceiptData.self
        )
    }
}
