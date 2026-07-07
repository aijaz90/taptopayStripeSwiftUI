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
        let url = APIConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        request.httpBody = bodyData

        print("🌐 [API] POST \(url.absoluteString)")
        print("🌐 [API] Request body: \(String(data: bodyData, encoding: .utf8) ?? "{}")")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Network-level failure (server down, wrong IP, no Wi-Fi, ATS blocked).
            print("❌ [API] Network error for \(path): \(error.localizedDescription)")
            throw APIError(message: "Network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            print("❌ [API] Non-HTTP response for \(path)")
            throw APIError(message: "Invalid server response.")
        }

        print("🌐 [API] Response \(http.statusCode) for \(path): \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

        // Read success / message first so failures (e.g. declined card,
        // 400/402/404) surface a clean message instead of a decode error.
        let status = try decoder.decode(APIStatus.self, from: data)
        guard status.success else {
            print("❌ [API] Server reported failure for \(path): \(status.message)")
            throw APIError(message: status.message)
        }

        guard (200...299).contains(http.statusCode) else {
            print("❌ [API] Non-2xx status \(http.statusCode) for \(path): \(status.message)")
            throw APIError(message: status.message)
        }

        let wrapper = try decoder.decode(APIResponse<T>.self, from: data)
        guard let payload = wrapper.data else {
            print("❌ [API] Missing data field for \(path)")
            throw APIError(message: "Missing data in server response.")
        }
        print("✅ [API] Decoded \(T.self) for \(path)")
        return payload
    }

    /// Sends a GET request and decodes `data` as `T`.
    func get<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        let url = APIConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        print("🌐 [API] GET \(url.absoluteString)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("❌ [API] Network error for \(path): \(error.localizedDescription)")
            throw APIError(message: "Network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid server response.")
        }
        print("🌐 [API] Response \(http.statusCode) for \(path): \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

        let status = try decoder.decode(APIStatus.self, from: data)
        guard status.success else { throw APIError(message: status.message) }
        guard (200...299).contains(http.statusCode) else { throw APIError(message: status.message) }

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

    /// GET /terminal_location — location id used to connect the Tap to Pay reader.
    func fetchLocation() async throws -> LocationData {
        try await get(path: APIConfig.Path.terminalLocation, as: LocationData.self)
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
