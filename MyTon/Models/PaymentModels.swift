//
//  PaymentModels.swift
//  MyTon
//
//  Decodable models mirroring the eventFun API responses.
//

import Foundation

/// Lightweight envelope used to read `success` / `message` before
/// attempting to decode the full typed payload.
struct APIStatus: Decodable {
    let success: Bool
    let message: String
}

/// Generic API response wrapper: { success, message, data }
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: T?
}

/// Data returned by POST /connection_token
struct ConnectionTokenData: Decodable {
    let secret: String
}

/// Data returned by POST /create_payment_intent
struct PaymentIntentData: Decodable {
    let id: String
    let amount: Int
    let currency: String
    let status: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, status
        case clientSecret = "client_secret"
    }
}

/// Data returned by POST /capture_payment and POST /receipt
struct ReceiptData: Decodable, Identifiable {
    var id: String { receiptId }

    let receiptId: String
    let paymentIntentId: String
    let merchant: String
    let amount: Int
    let currency: String
    let amountDisplay: String
    let status: String
    let cardBrand: String
    let cardLast4: String
    let date: String

    enum CodingKeys: String, CodingKey {
        case receiptId = "receipt_id"
        case paymentIntentId = "payment_intent_id"
        case merchant, amount, currency
        case amountDisplay = "amount_display"
        case status
        case cardBrand = "card_brand"
        case cardLast4 = "card_last4"
        case date
    }
}

/// Error surfaced to the UI when a request fails or the payment is declined.
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
